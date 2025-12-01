import os
import pickle
import time
from typing import Dict, List, Tuple

from dotenv import load_dotenv
from tqdm import tqdm
from pinecone import Pinecone

# =========================================
# .env 로드
# =========================================
load_dotenv()


class PineconeUploader:
    def __init__(self, use_local: bool = True):
        """Pinecone 초기화 & 설정"""
        self.use_local = use_local

        if use_local:
            # Pinecone Local
            self.pinecone_api_key = os.getenv("PINECONE_API_KEY", "local-test-key")
            self.pinecone_host = os.getenv("PINECONE_HOST", "http://localhost:5081")
            print(f"🔗 Pinecone Host: {self.pinecone_host}")
        else:
            # Pinecone Cloud
            self.pinecone_api_key = os.getenv("PINECONE_API_KEY")
            if not self.pinecone_api_key:
                raise ValueError("❌ PINECONE_API_KEY가 .env에 없습니다.")
            print("☁️ Pinecone Cloud 사용")

        print("✅ 환경 변수 로드 완료")

        # Pinecone
        try:
            self.pc = Pinecone(api_key=self.pinecone_api_key)
            print("✅ Pinecone 클라이언트 초기화 완료")
        except Exception as e:
            raise ValueError(f"❌ Pinecone 초기화 실패: {e}")

        # ===== 설정 =====
        self.index_name = "perfume-vectordb"
        self.namespace = ""  # 필요 시 분리
        self.upsert_batch_size = 10 if use_local else 100  # Local은 작은 배치

    # -------------------------------------
    # 인덱스 연결
    # -------------------------------------
    def connect_index(self) -> None:
        try:
            print(f"🔗 인덱스 '{self.index_name}' 연결 중...")
            if self.use_local:
                self.index = self.pc.Index(self.index_name, host=self.pinecone_host)
            else:
                self.index = self.pc.Index(self.index_name)
            print(f"✅ 인덱스 '{self.index_name}' 연결 완료")
        except Exception as e:
            raise ValueError(f"❌ 인덱스 연결 실패: {e}")

    # -------------------------------------
    # 파일에서 벡터 로드
    # -------------------------------------
    def load_vectors(self, file_path: str) -> List[Dict]:
        """pickle 파일에서 벡터 로드"""
        print(f"📂 벡터 로딩 중: {file_path}")
        with open(file_path, "rb") as f:
            vectors = pickle.load(f)
        print(f"✅ 벡터 {len(vectors)}개 로드 완료")
        return vectors

    # -------------------------------------
    # 업서트(배치)
    # -------------------------------------
    def upsert_vectors_batched(self, vectors: List[Dict]) -> Tuple[int, int]:
        if not vectors:
            return 0, 0
        ok, ng = 0, 0
        calls = 0
        print(f"📤 업서트(배치): batch={self.upsert_batch_size}")
        for i in tqdm(
            range(0, len(vectors), self.upsert_batch_size), desc="📦 업서트(batched)"
        ):
            batch = vectors[i : i + self.upsert_batch_size]
            try:
                res = self.index.upsert(vectors=batch, namespace=self.namespace)
                calls += 1
                if hasattr(res, "upserted_count") and isinstance(
                    res.upserted_count, int
                ):
                    ok += res.upserted_count
                else:
                    ok += len(batch)
            except Exception as e:
                ng += len(batch)
                print(f"⚠️ 업서트 실패 (i={i}): {e}")
                continue
            if (calls % 10) == 0:  # 10번마다 진행상황 출력
                print(
                    f"   ↳ call#{calls} batch_size={len(batch)} (누적 성공={ok}, 실패={ng})"
                )
            time.sleep(0.15 if self.use_local else 0.05)
        print(f"📞 업서트 호출수: {calls}")
        return ok, ng

    # -------------------------------------
    # 실행
    # -------------------------------------
    def run(self, vector_file: str) -> None:
        mode = "Pinecone Local" if self.use_local else "Pinecone Cloud"
        print(f"🚀 벡터 업로드 시작! ({mode})\n")

        # (1) 인덱스 연결
        self.connect_index()

        # (2) 파일에서 벡터 로드
        vectors = self.load_vectors(vector_file)
        if not vectors:
            print("❌ 로드할 벡터가 없습니다.")
            return

        # (3) Upsert (배치)
        ok, ng = self.upsert_vectors_batched(vectors)
        print(f"✅ 업서트 완료 | 성공: {ok}  실패: {ng}")

        # (4) 최종 통계
        try:
            stats = self.index.describe_index_stats()
            after = stats.get("total_vector_count", 0)
            print(f"\n📊 최종 벡터 수: {after}")
        except Exception as e:
            print(f"⚠️ 최종 통계 조회 실패: {e}")

        print("🎉 완료!")


# =========================================
# 메인
# =========================================
def main():
    import argparse

    parser = argparse.ArgumentParser(description="Pinecone에 벡터 업로드")
    parser.add_argument(
        "--file",
        type=str,
        default="perfume_embeddings.pkl",
        help="임베딩 파일 경로 (기본: perfume_embeddings.pkl)",
    )
    parser.add_argument(
        "--cloud",
        action="store_true",
        help="Pinecone Cloud 사용 (기본: Local)",
    )

    args = parser.parse_args()

    try:
        uploader = PineconeUploader(use_local=not args.cloud)
        uploader.run(args.file)
    except Exception as e:
        print(f"❌ 오류 발생: {e}")


if __name__ == "__main__":
    main()
