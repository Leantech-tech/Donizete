# Estágio 1: Build do Flutter
FROM debian:latest AS build-env

# Instala dependências básicas do sistema
RUN apt-get update && apt-get install -y \
    curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa \
    fonts-droid-fallback python3 xz-utils \
    && apt-get clean

# Baixa o Flutter SDK (Versão Stable)
RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter

# Adiciona o Flutter ao PATH do sistema
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Configura o ambiente
RUN flutter doctor -v
RUN flutter config --enable-web

# Define o diretório de trabalho principal
WORKDIR /app

# Copia todos os arquivos do repositório para o container
COPY . .

# AJUSTE DE CAMINHO: Entra na pasta onde o pubspec.yaml realmente está
# Pelas imagens, seu projeto está na pasta 'Donizete'
WORKDIR /app/Donizete

# Executa o build da aplicação web
RUN flutter pub get
RUN flutter build web --release --no-pub

# Estágio 2: Servidor Nginx para entrega dos arquivos estáticos
FROM nginx:alpine

# Limpa a pasta padrão do Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copia os arquivos compilados do estágio de build para o servidor Nginx
# Note que o caminho de origem também inclui a pasta 'Donizete'
COPY --from=build-env /app/Donizete/build/web /usr/share/nginx/html

# Expõe a porta padrão
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]