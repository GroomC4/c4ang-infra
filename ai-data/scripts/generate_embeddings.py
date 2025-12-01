import os
import re
import json
import hashlib
import pickle
from typing import Dict, Any, List, Optional
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from tqdm import tqdm
from openai import OpenAI
from langchain_core.documents import Document

# =========================================
# .env 로드
# =========================================
load_dotenv()

# =========================================
# 유틸
# =========================================
def _norm(s: Any) -> str:
    s = "" if s is None else str(s)
    s = s.strip()
    s = re.sub(r"\s+", " ", s)
    return s

def make_stable_id(brand: str, name: str) -> str:
    """브랜드+이름 기반 안정적 ID"""
    base = f"{brand.strip()}::{name.strip()}".lower()
    hid = hashlib.sha1(base.encode("utf-8")).hexdigest()[:16]
    return f"perfume_{hid}"

class EmbeddingGenerator:
    def __init__(self):
        """OpenAI 초기화 & 설정"""
        self.openai_api_key = os.getenv("OPENAI_API_KEY")

        if not self.openai_api_key:
            raise ValueError("❌ OPENAI_API_KEY가 .env에 없습니다.")

        print("✅ 환경 변수 로드 완료")

        # OpenAI
        try:
            self.openai = OpenAI(api_key=self.openai_api_key)
            print("✅ OpenAI 클라이언트 초기화 완료")
        except Exception as e:
            raise ValueError(f"❌ OpenAI 초기화 실패: {e}")

        # ===== 설정 =====
        self.embedding_model = "text-embedding-3-small"
        self.embed_batch_size = 128

    # -------------------------------------
    # CSV → Document
    # -------------------------------------
    def parse_score_string(self, score_str: str) -> Optional[str]:
        if pd.isna(score_str) or not str(score_str).strip() or str(score_str).lower() == "nan":
            return None
        try:
            s = str(score_str).strip()
            scores: Dict[str, float] = {}
            if "(" in s and ")" in s:
                pattern = r"(\w+)\s*\(\s*([\d.]+)\s*\)"
                for key, val in re.findall(pattern, s):
                    try:
                        scores[key.strip()] = float(val.strip())
                    except ValueError:
                        continue
            elif s.startswith("{") and s.endswith("}"):
                try:
                    d = json.loads(s)
                    for k, v in d.items():
                        if isinstance(v, str):
                            cv = v.replace("%", "").strip()
                            if cv:
                                scores[str(k)] = float(cv)
                        elif isinstance(v, (int, float)):
                            scores[str(k)] = float(v)
                except json.JSONDecodeError:
                    pass
            return max(scores, key=scores.get) if scores else None
        except Exception:
            return None

    def csv_to_documents(self, csv_path: str) -> List[Document]:
        # 상대 경로 처리: scripts/ 에서 실행되므로 ../data/ 참조
        if not os.path.isabs(csv_path):
            csv_path = os.path.join(os.path.dirname(__file__), "..", "data", csv_path)
        
        if not os.path.exists(csv_path):
            raise FileNotFoundError(f"❌ CSV 파일을 찾을 수 없습니다: {csv_path}")

        print(f"📖 CSV 로딩: {csv_path}")
        df = pd.read_csv(csv_path)
        print(f"📊 행 {len(df)}개")

        docs: List[Document] = []
        for _, row in tqdm(df.iterrows(), total=len(df), desc="🔄 Document 생성"):
            description = str(row.get("description", "")).strip()
            if not description or description.lower() == "nan":
                continue

            season_top = self.parse_score_string(str(row.get("season_score", "")))
            daynight_top = self.parse_score_string(str(row.get("day_night_score", "")))

            brand = _norm(row.get("brand", ""))
            name = _norm(row.get("name", ""))

            meta: Dict[str, Any] = {
                "id": make_stable_id(brand, name),
                "brand": brand,
                "name": name,
                "concentration": _norm(row.get("concentration", "")),
                "gender": _norm(row.get("gender", "")),
                "sizes": _norm(row.get("sizes", "")),
            }
            if season_top:
                meta["season_score"] = season_top
            if daynight_top:
                meta["day_night_score"] = daynight_top

            docs.append(Document(page_content=description, metadata=meta))

        print(f"✅ Document {len(docs)}개 생성 완료")
        return docs

    # -------------------------------------
    # 배치 임베딩
    # -------------------------------------
    def embed_batch(self, texts: List[str]) -> List[List[float]]:
        resp = self.openai.embeddings.create(model=self.embedding_model, input=texts)
        return [item.embedding for item in resp.data]

    def documents_to_vectors_batched(self, docs: List[Document]) -> List[Dict]:
        vectors: List[Dict] = []
        print(f"🔄 임베딩(배치) 생성: batch={self.embed_batch_size}")
        for i in tqdm(range(0, len(docs), self.embed_batch_size), desc="🧮 임베딩 배치"):
            batch_docs = docs[i : i + self.embed_batch_size]
            texts = [d.page_content for d in batch_docs]
            try:
                embs = self.embed_batch(texts)
                for d, emb in zip(batch_docs, embs):
                    meta = dict(d.metadata)
                    meta["text"] = d.page_content
                    vectors.append({"id": meta["id"], "values": emb, "metadata": meta})
            except Exception as e:
                print(f"⚠️ 임베딩 배치 실패 (i={i}): {e}")
                continue
        print(f"✅ 벡터 {len(vectors)}개 생성 완료")
        return vectors

    # -------------------------------------
    # 파일 저장
    # -------------------------------------
    def save_vectors(self, vectors: List[Dict], output_path: str) -> None:
        """벡터를 pickle 파일로 저장"""
        print(f"💾 벡터 저장 중: {output_path}")
        with open(output_path, "wb") as f:
            pickle.dump(vectors, f)
        print(f"✅ 저장 완료: {len(vectors)}개 벡터")

        # JSON으로도 저장 (사람이 읽을 수 있도록, 벡터는 제외)
        json_path = output_path.replace(".pkl", "_metadata.json")
        metadata_only = [
            {"id": v["id"], "metadata": v["metadata"]} for v in vectors[:10]
        ]  # 샘플만
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(metadata_only, f, ensure_ascii=False, indent=2)
        print(f"✅ 메타데이터 샘플 저장: {json_path}")

    # -------------------------------------
    # 실행
    # -------------------------------------
    def run(self, csv_path: str, output_path: str) -> None:
        print("🚀 임베딩 생성 시작!\n")

        # (1) CSV→Documents
        docs = self.csv_to_documents(csv_path)
        if not docs:
            print("❌ 변환할 문서가 없습니다.")
            return

        # (2) Documents→Vectors (배치 임베딩)
        vectors = self.documents_to_vectors_batched(docs)
        if not vectors:
            print("❌ 생성할 벡터가 없습니다.")
            return

        # (3) 파일로 저장
        self.save_vectors(vectors, output_path)

        print("\n🎉 완료!")
        print(f"📁 저장된 파일: {output_path}")
        print(f"📊 벡터 수: {len(vectors)}")


# =========================================
# 메인
# =========================================
def main():
    csv_file = "perfume_final.csv"
    output_file = "perfume_embeddings.pkl"

    try:
        generator = EmbeddingGenerator()
        generator.run(csv_file, output_file)
    except Exception as e:
        print(f"❌ 오류 발생: {e}")


if __name__ == "__main__":
    main()
