.PHONY: help start stop restart logs status setup clean upsert-perfume upsert-keyword

SCRIPTS_DIR := scripts

.PHONY: help start stop restart logs status setup clean embed upsert-local upsert-cloud

help: ## 사용 가능한 명령어 표시
	@echo "Pinecone Local 개발 환경"
	@echo ""
	@echo "사용법: make [command]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

start: ## Pinecone Local 컨테이너 시작
	@echo "🚀 Pinecone Local 시작 중..."
	docker-compose up -d
	@echo "✅ 컨테이너 시작 완료"
	@make status

stop: ## Pinecone Local 컨테이너 중지
	@echo "🛑 Pinecone Local 중지 중..."
	docker-compose down
	@echo "✅ 컨테이너 중지 완료"

restart: ## Pinecone Local 컨테이너 재시작
	@echo "🔄 Pinecone Local 재시작 중..."
	docker-compose restart
	@echo "✅ 컨테이너 재시작 완료"

logs: ## 컨테이너 로그 확인
	docker logs -f pinecone-local

status: ## 컨테이너 상태 확인
	@echo "📊 컨테이너 상태:"
	@docker ps | grep pinecone-local || echo "❌ 컨테이너가 실행 중이지 않습니다"
	@echo ""
	@echo "🔍 헬스체크:"
	@curl -s http://localhost:5081/ > /dev/null && echo "✅ Pinecone Local 정상 작동 중" || echo "❌ Pinecone Local 응답 없음"

setup: ## Python 환경 설정 (가상환경 + 의존성)
	@echo "🔧 Python 환경 설정 중..."
	cd $(SCRIPTS_DIR) && python3 -m venv venv
	cd $(SCRIPTS_DIR) && . venv/bin/activate && pip install --upgrade pip
	cd $(SCRIPTS_DIR) && . venv/bin/activate && pip install -r requirements.txt
	@echo "✅ Python 환경 설정 완료"
	@echo ""
	@echo "📝 다음 단계:"
	@echo "  1. cp .env.example .env"
	@echo "  2. .env 파일에서 OPENAI_API_KEY 설정"
	@echo "  3. cd $(SCRIPTS_DIR)"
	@echo "  4. source venv/bin/activate"
	@echo "  5. python generate_embeddings.py"

clean: ## 가상환경 및 캐시 삭제
	@echo "🧹 정리 중..."
	rm -rf $(SCRIPTS_DIR)/venv
	rm -rf $(SCRIPTS_DIR)/__pycache__
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	@echo "✅ 정리 완료"

embed: ## 임베딩 생성 (파일로 저장)
	@echo "🧮 임베딩 생성 중..."
	cd $(SCRIPTS_DIR) && . venv/bin/activate && python generate_embeddings.py

upsert-local: ## 로컬 Pinecone에 업서트 (임베딩 파일 필요)
	@echo "📤 로컬 Pinecone에 업서트 중..."
	cd $(SCRIPTS_DIR) && . venv/bin/activate && python upsert_from_file.py

upsert-cloud: ## 클라우드 Pinecone에 업서트 (임베딩 파일 필요)
	@echo "📤 클라우드 Pinecone에 업서트 중..."
	cd $(SCRIPTS_DIR) && . venv/bin/activate && python upsert_from_file.py --cloud

init: start setup ## 전체 초기 설정 (컨테이너 시작 + Python 환경)
	@echo ""
	@echo "🎉 초기 설정 완료!"
	@echo ""
	@echo "📝 다음 단계:"
	@echo "  1. cp .env.example .env"
	@echo "  2. .env 파일에서 OPENAI_API_KEY 설정"
	@echo "  3. make embed          # 임베딩 생성"
	@echo "  4. make upsert-local   # 로컬에 업로드"
