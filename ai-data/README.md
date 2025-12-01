# Pinecone Local 개발 환경

로컬에서 Pinecone을 테스트하기 위한 Docker 기반 환경입니다.

## 디렉토리 구조

```
pinecone-local-dev/
├── docker-compose.yml          # Pinecone Local 컨테이너 설정
├── .env.example                # 환경 변수 템플릿
├── .env                        # 환경 변수 (gitignore)
├── Makefile                    # 편리한 명령어 모음
├── README.md                   # 이 파일
├── data/                       # 원본 데이터
│   ├── perfume_final.csv
│   └── keyword_dictionary_final.csv
└── scripts/                    # Python 스크립트
    ├── generate_embeddings.py      # 임베딩 생성 → 파일 저장
    ├── upsert_from_file.py         # 파일 → Pinecone 업로드
    ├── requirements.txt            # Python 의존성
    └── venv/                       # 가상환경 (gitignore)
```

## 빠른 시작

### 1. 전체 초기 설정

```bash
make init
```

이 명령어는 다음을 자동으로 수행합니다:
- Pinecone Local Docker 컨테이너 시작
- Python 가상환경 생성
- 필요한 패키지 설치

### 2. 환경 변수 설정

```bash
# .env.example을 .env로 복사
cp .env.example .env

# .env 파일 편집하여 OpenAI API 키 설정
nano .env
```

`.env` 파일 내용:
```bash
PINECONE_API_KEY=local-test-key
PINECONE_HOST=http://localhost:5081
OPENAI_API_KEY=sk-your-actual-openai-key
```

### 3. 임베딩 생성 및 업로드

```bash
# 임베딩 생성 (한 번만)
make embed

# 로컬 Pinecone에 업로드
make upsert-local

# 클라우드 Pinecone에 업로드 (선택사항)
make upsert-cloud
```

## 주요 명령어

```bash
make help            # 사용 가능한 명령어 확인
make init            # 전체 초기 설정
make start           # Pinecone Local 시작
make stop            # Pinecone Local 중지
make status          # 상태 확인
make logs            # 로그 확인

# 임베딩 & 업서트
make embed           # 임베딩 생성
make upsert-local    # 로컬에 업로드
make upsert-cloud    # 클라우드에 업로드
```

## 워크플로우

### 권장 방식: 임베딩 재사용

1. **임베딩 생성 (한 번만 실행)**
   ```bash
   cd scripts
   source venv/bin/activate
   python generate_embeddings.py
   ```
   - `data/perfume_final.csv` 읽기
   - OpenAI로 임베딩 생성
   - `scripts/perfume_embeddings.pkl` 저장
   - 비용 발생 (한 번만)

2. **Pinecone에 업로드 (여러 번 가능)**
   ```bash
   # 로컬
   python upsert_from_file.py
   
   # 클라우드
   python upsert_from_file.py --cloud
   
   # 커스텀 파일
   python upsert_from_file.py --file custom.pkl
   ```
   - 저장된 임베딩 파일 읽기
   - Pinecone에 업로드
   - OpenAI API 호출 없음 (무료)

## 스크립트 설명

### generate_embeddings.py
- CSV 파일을 읽어서 OpenAI 임베딩 생성
- pickle 파일로 저장 (`perfume_embeddings.pkl`)
- 메타데이터 샘플 JSON 파일도 생성

### upsert_from_file.py
- 저장된 임베딩 파일을 Pinecone에 업로드
- `--cloud` 옵션으로 Local/Cloud 선택
- `--file` 옵션으로 커스텀 파일 지정

## 환경별 차이점

| 항목 | Local | Cloud |
|------|-------|-------|
| 연결 방식 | `host=http://localhost:5081` | Pinecone Cloud API |
| 인덱스 생성 | Docker 환경 변수로 자동 | `ServerlessSpec` 사용 |
| 업서트 배치 크기 | 10 (페이로드 제한) | 100 |
| API 키 | 임의 값 가능 | 실제 Pinecone API 키 필요 |

## 문제 해결

### OpenAI API 할당량 초과
- https://platform.openai.com/account/billing 에서 크레딧 확인
- 결제 정보 등록 필요

### Payload Too Large 오류
- Local 환경에서 배치 크기가 너무 큼
- `upsert_batch_size`를 더 작게 조정 (현재 10)

### 인덱스 연결 실패
- Docker 컨테이너가 실행 중인지 확인: `make status`
- 헬스체크: `curl http://localhost:5081/`

## 컨테이너 관리

```bash
make start           # 시작
make stop            # 중지
make restart         # 재시작
make logs            # 로그 확인
make status          # 상태 확인
```

## 가상환경 관리

```bash
# 활성화
cd scripts
source venv/bin/activate

# 비활성화
deactivate

# 삭제 (필요시)
make clean
```

## 생성되는 파일

```
scripts/
├── perfume_embeddings.pkl              # 임베딩 벡터 (gitignore)
└── perfume_embeddings_metadata.json    # 메타데이터 샘플 (gitignore)
```

이 파일들은 `.gitignore`에 포함되어 있어 Git에 커밋되지 않습니다.
