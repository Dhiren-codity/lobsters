# Metadata Service

A high-performance Go microservice for fetching and caching URL metadata (title, description, images, etc.) for the Lobsters application.

## Features

- Fast URL metadata extraction (title, description, Open Graph tags)
- In-memory caching with TTL (24 hours default)
- Automatic cache cleanup
- Graceful shutdown
- Health check endpoint
- Concurrent request handling

## API

### POST /fetch

Fetches metadata for a given URL.

Request:
```json
{
  "url": "https://example.com/article"
}
```

Response:
```json
{
  "metadata": {
    "url": "https://example.com/article",
    "title": "Article Title",
    "description": "Article description...",
    "site_name": "Example Site",
    "image_url": "https://example.com/image.jpg"
  },
  "cached": false
}
```

### GET /health

Health check endpoint.

## Configuration

- `PORT`: Server port (default: 8080)

## Running

```bash
cd services/metadata-service
go run main.go
```

Or with custom port:
```bash
PORT=3001 go run main.go
```

