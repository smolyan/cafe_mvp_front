# ---------- СТАДИЯ 1: СБОРКА FLUTTER WEB ----------
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Копируем манифесты заранее (для кэширования)
COPY pubspec.* ./
RUN flutter pub get

# Копируем остальной проект и собираем
COPY . .
RUN flutter build web --release

# ---------- СТАДИЯ 2: СЕРВЕР СТАТИКИ ----------
FROM python:3.12-alpine

WORKDIR /app

# Копируем собранный билд
COPY --from=build /app/build/web ./build

# Railway передаёт порт через env PORT
ENV PORT=8080
EXPOSE 8080

# Простой http-сервер Python
CMD ["sh", "-c", "python -m http.server $PORT -d build"]
