FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Cloud Run sets PORT env var; default to 8000 locally
ENV PORT=8000

CMD uvicorn main:app --host 0.0.0.0 --port $PORT
