# Используем официальный образ Go для сборки
FROM golang:1.21-alpine AS builder

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем go.mod и go.sum (если есть)
COPY go.* ./

# Загружаем зависимости
RUN go mod download

# Копируем исходный код
COPY . .

# Собираем приложение
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# Используем минимальный образ для финального контейнера
FROM alpine:latest

# Устанавливаем необходимые пакеты
RUN apk --no-cache add ca-certificates

# Создаем пользователя для безопасности
RUN addgroup -g 1000 appgroup && adduser -u 1000 -G appgroup -s /bin/sh -D appuser

# Устанавливаем рабочую директорию
WORKDIR /root/

# Копируем собранное приложение из builder
COPY --from=builder /app/main .

# Меняем владельца файла
RUN chown appuser:appgroup ./main

# Переключаемся на пользователя appuser
USER appuser

# Открываем порт
EXPOSE 8080

# Запускаем приложение
CMD ["./main"]