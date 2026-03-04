# ---------------------------------------------------------
# ESTÁGIO 1: Build (Onde a mágica acontece)
# ---------------------------------------------------------
FROM node:22-bookworm-slim AS build
WORKDIR /app

# Variáveis de ambiente para o build
ENV HUSKY=0 \
    CI=true \
    NODE_ENV=development

# Instalar dependências de sistema essenciais (git, python, g++ são vitais para pacotes nativos)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    make \
    g++ \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Ativar e configurar o PNPM (Versão estável 9.x)
RUN corepack enable && corepack prepare pnpm@9.15.9 --activate

# Copiar APENAS os arquivos de dependências primeiro (otimiza o cache do Docker)
# O asterisco garante que o build não quebre se o lockfile não existir (embora deva existir)
COPY package.json pnpm-lock.yaml* ./

# Instalar TODAS as dependências (necessário incluir as de dev para rodar o build do Remix)
RUN pnpm install --frozen-lockfile

# Agora sim, copiar o restante dos arquivos do projeto
COPY . .

# Argumento de build para URL pública (essencial para o marketing/SEO das LPs)
ARG VITE_PUBLIC_APP_URL
ENV VITE_PUBLIC_APP_URL=${VITE_PUBLIC_APP_URL}

# Executar o build do Remix/Vite com limite de memória aumentado (8GB do seu servidor permitem isso)
# Isso evita o erro "remix: not found" pois o binário estará no node_modules
RUN NODE_OPTIONS=--max-old-space-size=6144 pnpm run build

# ---------------------------------------------------------
# ESTÁGIO 3: Produção (Opcional, mas aqui está para ser completo)
# ---------------------------------------------------------
FROM build AS bolt-ai-production
WORKDIR /app

ENV NODE_ENV=production \
    PORT=5173 \
    HOST=0.0.0.0 \
    RUNNING_IN_DOCKER=true

# Limpa dependências de dev para economizar espaço
RUN pnpm prune --prod --ignore-scripts

EXPOSE 5173

# Healthcheck: Garante que o Easypanel saiba se o app travou
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:5173/ || exit 1

# Comando de produção (pode exigir ajustes no bindings.sh do repositório)
CMD ["pnpm", "run", "dockerstart"]

# ---------------------------------------------------------
# ESTÁGIO 2: Desenvolvimento (Ideal para seu Easypanel)
# ---------------------------------------------------------
FROM build AS development

# Variáveis para rodar no Docker do seu servidor
ENV PORT=5173 \
    HOST=0.0.0.0 \
    RUNNING_IN_DOCKER=true \
    VITE_LOG_LEVEL=info

EXPOSE 5173

# O comando 'dev' é o mais estável para evitar conflitos com o Wrangler/Cloudflare
CMD ["pnpm", "run", "dev", "--host"]
