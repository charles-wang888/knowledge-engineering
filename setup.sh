#!/bin/bash
set -e

echo "=========================================="
echo "  knowledge-engineering 一键部署脚本"
echo "=========================================="

cd "$(dirname "$0")"
PROJECT_ROOT="$(pwd)"

# ============ Step 1: Python venv ============
echo ""
echo "[1/5] 创建 Python 虚拟环境..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "  ✅ venv 已创建"
else
    echo "  ✅ venv 已存在，跳过"
fi
source venv/bin/activate
echo "  Python: $(python --version)"

# ============ Step 2: 安装依赖 ============
echo ""
echo "[2/5] 安装 Python 依赖..."
pip install --upgrade pip -q
pip install -e "." -q 2>/dev/null || pip install -e ".[neo4j]" -q 2>/dev/null || {
    echo "  尝试直接安装 requirements.txt..."
    pip install -r requirements.txt -q
}

# 安装可选依赖
pip install weaviate-client -q 2>/dev/null && echo "  ✅ weaviate-client" || echo "  ⚠ weaviate-client 安装失败"
pip install openai -q 2>/dev/null && echo "  ✅ openai" || echo "  ⚠ openai 安装失败"
pip install neo4j -q 2>/dev/null && echo "  ✅ neo4j" || echo "  ⚠ neo4j 安装失败"
pip install rdflib -q 2>/dev/null && echo "  ✅ rdflib" || echo "  ⚠ rdflib 安装失败"
echo "  ✅ Python 依赖安装完成"

# ============ Step 3: Docker 服务 ============
echo ""
echo "[3/5] 启动 Docker 服务 (Neo4j + Weaviate)..."
if command -v docker &>/dev/null; then
    if command -v docker-compose &>/dev/null; then
        docker-compose up -d
    elif docker compose version &>/dev/null 2>&1; then
        docker compose up -d
    else
        echo "  ⚠ docker-compose 不可用，尝试单独启动..."
        docker run -d --name ke-neo4j -e NEO4J_AUTH=neo4j/12345678 -p 7474:7474 -p 7687:7687 neo4j:5-community 2>/dev/null || echo "  Neo4j 可能已在运行"
        docker run -d --name ke-weaviate -e AUTHENTICATION_APIKEY_ENABLED=true -e AUTHENTICATION_APIKEY_ALLOWED_KEYS=user-a-key -e DEFAULT_VECTORIZER_MODULE=none -p 8080:8080 -p 50051:50051 semitechnologies/weaviate:1.28.4 2>/dev/null || echo "  Weaviate 可能已在运行"
    fi
    echo "  ✅ Docker 服务已启动"
    echo "  Neo4j Web: http://localhost:7474 (neo4j/12345678)"
    echo "  Weaviate:  http://localhost:8080"
else
    echo "  ❌ Docker 未安装！请安装 Docker Desktop 后重新运行"
    echo "  或者修改 config/project.yaml 将 backend 改为 memory"
fi

# ============ Step 4: Ollama ============
echo ""
echo "[4/5] 检查 Ollama..."
if command -v ollama &>/dev/null; then
    echo "  ✅ Ollama 已安装"
    # 检查 bge-m3 模型
    if ollama list 2>/dev/null | grep -q "bge-m3"; then
        echo "  ✅ bge-m3 模型已就绪"
    else
        echo "  拉取 bge-m3 嵌入模型（约 700MB）..."
        ollama pull bge-m3 || echo "  ⚠ bge-m3 拉取失败，请手动: ollama pull bge-m3"
    fi
else
    echo "  ⚠ Ollama 未安装"
    echo "  如果使用云端LLM（Qwen/MiniMax），嵌入模型仍需要本地Ollama"
    echo "  安装: https://ollama.ai 或 brew install ollama"
    echo "  安装后执行: ollama pull bge-m3"
fi

# ============ Step 5: 校验配置 ============
echo ""
echo "[5/5] 校验配置..."
REPO_PATH=$(python -c "import yaml; c=yaml.safe_load(open('config/project.yaml')); print(c['repo']['path'])" 2>/dev/null)
if [ -d "$REPO_PATH" ]; then
    JAVA_COUNT=$(find "$REPO_PATH" -name "*.java" -not -path "*/target/*" 2>/dev/null | wc -l | tr -d ' ')
    echo "  ✅ repo.path: $REPO_PATH"
    echo "  ✅ Java 文件数: $JAVA_COUNT"
else
    echo "  ❌ repo.path 无效: $REPO_PATH"
    echo "  请修改 config/project.yaml 第 3 行"
fi

# ============ 完成 ============
echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "  启动方式:"
echo "    source venv/bin/activate"
echo "    python main.py              # Streamlit UI (推荐)"
echo "    # 或"
echo "    python -m src.pipeline.cli  # 命令行模式"
echo ""
echo "  服务地址:"
echo "    Streamlit:  http://localhost:8501"
echo "    FastAPI:    http://localhost:8000"
echo "    Neo4j:      http://localhost:7474"
echo "    Weaviate:   http://localhost:8080"
echo ""
