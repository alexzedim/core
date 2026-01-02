# Qdrant Quick Start Guide

## What is Qdrant?

Qdrant is a production-ready vector database designed for semantic search and AI applications. It stores and searches high-dimensional vectors (embeddings) efficiently using the HNSW algorithm.

## Quick Start (5 minutes)

### 1. Start Qdrant
```bash
docker-compose -f docker-compose.ai.yml up -d qdrant
```

### 2. Verify it's running
```bash
curl http://localhost:6333/health
# Response: {"status":"ok"}
```

### 3. Create a collection
```bash
curl -X PUT "http://localhost:6333/collections/my_collection" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 1536,
      "distance": "Cosine"
    }
  }'
```

### 4. Add vectors
```bash
curl -X PUT "http://localhost:6333/collections/my_collection/points" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.1, 0.2, 0.3, ...],
        "payload": {"text": "Hello world"}
      },
      {
        "id": 2,
        "vector": [0.2, 0.3, 0.4, ...],
        "payload": {"text": "Goodbye world"}
      }
    ]
  }'
```

### 5. Search
```bash
curl -X POST "http://localhost:6333/collections/my_collection/points/search" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, ...],
    "limit": 10
  }'
```

## Common Operations

### List Collections
```bash
curl -X GET "http://localhost:6333/collections" \
  -H "api-key: your_api_key"
```

### Get Collection Info
```bash
curl -X GET "http://localhost:6333/collections/my_collection" \
  -H "api-key: your_api_key"
```

### Delete Collection
```bash
curl -X DELETE "http://localhost:6333/collections/my_collection" \
  -H "api-key: your_api_key"
```

### Update Point
```bash
curl -X PUT "http://localhost:6333/collections/my_collection/points" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.15, 0.25, 0.35, ...],
        "payload": {"text": "Updated text"}
      }
    ]
  }'
```

### Delete Point
```bash
curl -X POST "http://localhost:6333/collections/my_collection/points/delete" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [1, 2]
  }'
```

## Python Client Example

### Install client
```bash
pip install qdrant-client
```

### Basic usage
```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

# Connect to Qdrant
client = QdrantClient("localhost", port=6333, api_key="your_api_key")

# Create collection
client.create_collection(
    collection_name="my_collection",
    vectors_config=VectorParams(size=1536, distance=Distance.COSINE),
)

# Add vectors
client.upsert(
    collection_name="my_collection",
    points=[
        PointStruct(
            id=1,
            vector=[0.1, 0.2, 0.3, ...],
            payload={"text": "Hello world"}
        ),
        PointStruct(
            id=2,
            vector=[0.2, 0.3, 0.4, ...],
            payload={"text": "Goodbye world"}
        ),
    ],
)

# Search
results = client.search(
    collection_name="my_collection",
    query_vector=[0.1, 0.2, 0.3, ...],
    limit=10,
)

for result in results:
    print(f"ID: {result.id}, Score: {result.score}, Payload: {result.payload}")
```

## Node.js Client Example

### Install client
```bash
npm install @qdrant/js-client-rest
```

### Basic usage
```javascript
import { QdrantClient } from "@qdrant/js-client-rest";

const client = new QdrantClient({
  url: "http://localhost:6333",
  apiKey: "your_api_key",
});

// Create collection
await client.createCollection("my_collection", {
  vectors: {
    size: 1536,
    distance: "Cosine",
  },
});

// Add vectors
await client.upsert("my_collection", {
  points: [
    {
      id: 1,
      vector: [0.1, 0.2, 0.3, ...],
      payload: { text: "Hello world" },
    },
    {
      id: 2,
      vector: [0.2, 0.3, 0.4, ...],
      payload: { text: "Goodbye world" },
    },
  ],
});

// Search
const results = await client.search("my_collection", {
  vector: [0.1, 0.2, 0.3, ...],
  limit: 10,
});

results.forEach((result) => {
  console.log(`ID: ${result.id}, Score: ${result.score}, Payload:`, result.payload);
});
```

## Integration with OpenAI Embeddings

### Python example
```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
import openai

# Initialize clients
qdrant = QdrantClient("localhost", port=6333, api_key="your_api_key")
openai.api_key = "your_openai_api_key"

# Create collection
qdrant.create_collection(
    collection_name="documents",
    vectors_config=VectorParams(size=1536, distance=Distance.COSINE),
)

# Embed and store documents
documents = [
    "The quick brown fox jumps over the lazy dog",
    "Machine learning is a subset of artificial intelligence",
    "Qdrant is a vector database for semantic search",
]

points = []
for i, doc in enumerate(documents):
    # Get embedding from OpenAI
    response = openai.Embedding.create(
        input=doc,
        model="text-embedding-3-small"
    )
    embedding = response["data"][0]["embedding"]
    
    points.append(
        PointStruct(
            id=i,
            vector=embedding,
            payload={"text": doc}
        )
    )

# Store in Qdrant
qdrant.upsert(collection_name="documents", points=points)

# Search
query = "What is machine learning?"
query_embedding = openai.Embedding.create(
    input=query,
    model="text-embedding-3-small"
)["data"][0]["embedding"]

results = qdrant.search(
    collection_name="documents",
    query_vector=query_embedding,
    limit=3,
)

for result in results:
    print(f"Score: {result.score:.4f}, Text: {result.payload['text']}")
```

## Monitoring

### Check Qdrant metrics
```bash
curl http://localhost:6333/metrics
```

### View in Prometheus
- URL: `https://prometheus.cmnw.ru`
- Search for: `qdrant_*`

### View in Grafana
- URL: `https://grafana.cmnw.ru`
- Create dashboard with Prometheus data source
- Use metrics: `qdrant_collections_total`, `qdrant_points_total`, etc.

## Performance Tips

1. **Batch operations**: Use batch upsert for better performance
   ```bash
   curl -X PUT "http://localhost:6333/collections/my_collection/points" \
     -H "api-key: your_api_key" \
     -H "Content-Type: application/json" \
     -d '{
       "points": [
         {"id": 1, "vector": [...], "payload": {...}},
         {"id": 2, "vector": [...], "payload": {...}},
         ...
       ]
     }'
   ```

2. **Use filters**: Reduce search space with payload filters
   ```bash
   curl -X POST "http://localhost:6333/collections/my_collection/points/search" \
     -H "api-key: your_api_key" \
     -H "Content-Type: application/json" \
     -d '{
       "vector": [...],
       "filter": {
         "must": [
           {
             "key": "category",
             "match": {"value": "news"}
           }
         ]
       },
       "limit": 10
     }'
   ```

3. **Optimize vector size**: Use smaller vectors if possible
   - 384 dimensions: Fast, good for simple tasks
   - 768 dimensions: Balanced
   - 1536 dimensions: High quality (OpenAI default)

4. **Enable snapshots**: Automatic backups every 10 minutes

## Troubleshooting

### Connection refused
```bash
# Check if Qdrant is running
docker ps | grep qdrant

# Check logs
docker-compose -f docker-compose.ai.yml logs qdrant

# Test connectivity
curl http://localhost:6333/health
```

### API key errors
```bash
# Verify API key in request
curl -X GET "http://localhost:6333/collections" \
  -H "api-key: your_correct_api_key"
```

### Collection not found
```bash
# List all collections
curl -X GET "http://localhost:6333/collections" \
  -H "api-key: your_api_key"

# Create collection if missing
curl -X PUT "http://localhost:6333/collections/my_collection" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 1536,
      "distance": "Cosine"
    }
  }'
```

### High memory usage
```bash
# Check collection sizes
curl -X GET "http://localhost:6333/collections" \
  -H "api-key: your_api_key"

# Delete unused collections
curl -X DELETE "http://localhost:6333/collections/old_collection" \
  -H "api-key: your_api_key"
```

## Next Steps

1. Read the full documentation: [`docs/AI_COMPOSE_SETUP.md`](AI_COMPOSE_SETUP.md)
2. Check the migration summary: [`docs/AI_MIGRATION_SUMMARY.md`](AI_MIGRATION_SUMMARY.md)
3. Explore Qdrant docs: https://qdrant.tech/documentation/
4. Try the Python client: https://github.com/qdrant/qdrant-client
5. Join the community: https://discord.gg/qdrant

## Useful Links

- **Qdrant REST API**: http://localhost:6333/api/docs
- **Qdrant Web UI**: http://localhost:6333/dashboard
- **Prometheus**: https://prometheus.cmnw.ru
- **Grafana**: https://grafana.cmnw.ru
- **Nginx Reverse Proxy**: https://qdrant.cmnw.ru

## Support

For issues or questions:
1. Check the logs: `docker-compose -f docker-compose.ai.yml logs qdrant`
2. Review the documentation: `docs/AI_COMPOSE_SETUP.md`
3. Check Qdrant health: `curl http://localhost:6333/health`
4. Visit Qdrant Discord: https://discord.gg/qdrant
