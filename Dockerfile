# Estágio 1: Build do Flutter
FROM debian:latest AS build-env

# Instala dependências básicas
RUN apt-get update && apt-get install -y \
    curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa \
    fonts-droid-fallback python3 xz-utils \
    && apt-get clean

# Baixa o Flutter SDK
RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter

# Adiciona ao PATH
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Pré-download dos artefatos de desenvolvimento
RUN flutter doctor -v
RUN flutter config --enable-web

WORKDIR /app
COPY . .

# Garante que as dependências sejam baixadas e o build ocorra
RUN flutter pub get
# Adicionamos o --no-pub para garantir que ele use o que foi baixado acima
RUN flutter build web --release --no-pub

# Estágio 2: Nginx
FROM nginx:alpine
# Limpa o diretório padrão do Nginx antes de copiar
RUN rm -rf /usr/share/nginx/html/*
COPY --from=build-env /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]