# Streaming Optimization
## Wheeler AI Routing -- Phase 7 Optimization

### Current State: All calls use blocking (non-streaming) completions. No time-to-first-token (TTFT) optimization.

---

## 1. WHY STREAMING MATTERS

### 1.1 Current Latency Profile (Estimated)

For a typical 500-token response at 50 tokens/second:

| Phase | Duration (non-streaming) | Duration (streaming) |
|-------|--------------------------|---------------------|
| Request + auth | 200ms | 200ms |
| Model processing (TTFT) | 500ms | 500ms (first token visible) |
| Token generation | 10s | 10s (but user sees tokens as they arrive) |
| **Total before user sees result** | **10.7s** | **0.7s** |
| **Perceived latency** | 10.7s | 0.7s (TTFT) |

Streaming reduces **perceived latency** by ~93% for a 500-token response.

### 1.2 Use Cases for Streaming

| Use Case | Streaming? | Reason |
|----------|-----------|--------|
| Chat/UI interactions | YES | Users see immediate feedback |
| OpenClaw dashboard | YES | Agent responses stream to dashboard |
| Voice agent responses | YES | TTFT matters for natural conversation |
| Batch processing / reports | NO | No user waiting, save overhead |
| API-to-API calls | NO | Caller is another service, not a human |
| Embedding generation | N/A | Not applicable (no streaming for embeddings) |

---

## 2. LITELLM CONFIGURATION

### 2.1 Enable Streaming Globally

```yaml
litellm_settings:
  stream: true                   # Enable streaming support at proxy level
  stream_timeout: 60             # Global stream timeout (seconds)
  stream_chunk_size: 4096        # Chunk size for SSE streaming
```

### 2.2 Per-Model Streaming Settings

```yaml
model_list:
  - model_name: deepseek-chat
    litellm_params:
      stream_timeout: 15         # Flash should start streaming within 15s

  - model_name: deepseek-reasoner
    litellm_params:
      stream_timeout: 30         # Reasoner may need more time to start

  - model_name: claude-sonnet-4
    litellm_params:
      stream_timeout: 30

  - model_name: claude-opus-4
    litellm_params:
      stream_timeout: 45
```

---

## 3. CLIENT-SIDE STREAMING

### 3.1 Python (llm_client.py) -- Streaming Version

```python
import json
from typing import AsyncIterator, Optional

@observe(as_type="generation")
async def llm_stream_async(
    messages: list[dict],
    model: str = DEFAULT_MODEL,
    temperature: float = 0.7,
    max_tokens: int = 2048,
    agent: Optional[str] = None,
    workflow: Optional[str] = None,
) -> AsyncIterator[str]:
    """Stream LLM response token by token. Use for UI-facing calls."""
    _start = time.monotonic()

    langfuse_context.update_current_observation(
        name=f"llm-stream-{agent or 'async'}",
        input=messages,
        metadata={
            "agent": agent,
            "workflow": workflow,
            "model": model,
            "temperature": temperature,
            "streaming": True,
        },
        model=model,
        model_parameters={
            "temperature": temperature,
            "max_tokens": max_tokens,
        },
    )

    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": True,               # Request streaming from LiteLLM
    }

    headers = {"Content-Type": "application/json"}
    if LITELLM_KEY:
        headers["Authorization"] = f"Bearer {LITELLM_KEY}"

    full_content = []
    input_tokens = 0
    output_tokens = 0

    try:
        async with httpx.AsyncClient(timeout=120) as client:
            async with client.stream(
                "POST",
                f"{LITELLM_URL}/chat/completions",
                json=payload,
                headers=headers,
            ) as response:
                response.raise_for_status()

                async for line in response.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    if line == "data: [DONE]":
                        break

                    try:
                        chunk = json.loads(line[6:])  # Strip "data: " prefix
                    except json.JSONDecodeError:
                        continue

                    # Extract content delta
                    delta = chunk.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        full_content.append(content)
                        yield content

                    # Accumulate usage from final chunk
                    usage = chunk.get("usage", {})
                    if usage:
                        input_tokens = usage.get("prompt_tokens", 0)
                        output_tokens = usage.get("completion_tokens", 0)

    except Exception as e:
        logger.warning("[llm_client] Stream failed (model=%s): %s", model, e)
        langfuse_context.update_current_observation(
            level="ERROR",
            status_message=str(e),
        )
        raise

    finally:
        # Log completion
        full_text = "".join(full_content)
        duration_ms = int((time.monotonic() - _start) * 1000)

        if output_tokens == 0:
            output_tokens = len(full_text) // 4  # Rough estimate

        cost = _calculate_cost(model, input_tokens, output_tokens)
        langfuse_context.update_current_observation(
            output=full_text,
            usage={
                "input": input_tokens,
                "output": output_tokens,
                "unit": "TOKENS",
            },
        )
        _log_cost(agent, workflow, model, input_tokens, output_tokens,
                  cost, "success", None, duration_ms)


# Non-streaming variant (keep for batch jobs)
async def llm_complete_async(messages, model=DEFAULT_MODEL, ...):
    """Non-streaming: collects full response before returning. Use for batch jobs."""
    chunks = []
    async for chunk in llm_stream_async(messages, model, ...):
        chunks.append(chunk)
    return "".join(chunks)
```

### 3.2 Node.js (model.js) -- Streaming Support

```javascript
// New streaming model for agent-svc
async function* streamCompletion(messages, modelId = 'deepseek-chat') {
    const response = await fetch(`${LITELLM_URL}/v1/chat/completions`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${LITELLM_KEY}`,
        },
        body: JSON.stringify({
            model: modelId,
            messages,
            stream: true,
            max_tokens: 2048,
        }),
    });

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
        const {done, value} = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, {stream: true});
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
            if (!line.startsWith('data: ') || line === 'data: [DONE]') continue;
            try {
                const chunk = JSON.parse(line.slice(6));
                const content = chunk.choices?.[0]?.delta?.content;
                if (content) yield content;
            } catch (e) {
                // Skip malformed chunks
            }
        }
    }
}
```

---

## 4. STREAMING ROUTING DECISIONS

### Decision Logic

```python
def should_stream(agent: str, task_type: str, is_interactive: bool) -> bool:
    """Decide whether to use streaming based on context."""

    # Never stream for batch/background jobs
    if not is_interactive:
        return False

    # Always stream for user-facing interactions
    if agent in ("voice-agent-svc", "frgcrm-agent-svc"):
        return True

    # Stream for dashboard/UI calls
    if agent == "openclaw-dashboard":
        return True

    # Don't stream for simple classification/extraction
    if task_type in ("classification", "extraction"):
        return False  # Small response, streaming overhead not worth it

    # Stream for generation/analysis (larger responses)
    if task_type in ("generation", "analysis", "summarization"):
        return True

    return False
```

---

## 5. STREAMING OVERHEAD CONSIDERATIONS

### 5.1 Connection Cost

Streaming keeps an HTTP connection open for the duration of generation. With 10 concurrent streams:
- 10 open TCP connections to LiteLLM
- 10 open connections from LiteLLM to DeepSeek (or Claude)
- Memory: ~10KB per active stream buffer

**Mitigation**: Set `stream_timeout` to close stale connections.

### 5.2 Token Counting

With streaming, you don't know the total token count until the stream ends. Langfuse should be updated in the finally block with the full count.

### 5.3 Error Handling

Streaming errors are harder to detect than non-streaming (you get partial responses before realizing the error). Always:
- Check HTTP status code before starting to read chunks
- Set a stream timeout
- Have a fallback path (non-streaming retry) if streaming fails

---

## 6. IMPLEMENTATION CHECKLIST

- [ ] Set `stream: true` in LiteLLM config
- [ ] Configure `stream_timeout` per model
- [ ] Add `llm_stream_async()` function to llm_client.py
- [ ] Add streaming support to Node.js agent model.js
- [ ] Add `should_stream()` routing logic
- [ ] Update Langfuse instrumentation for streamed calls
- [ ] Add TTFT (time-to-first-token) metric to monitoring
- [ ] Test with OpenClaw dashboard (verify tokens appear as they arrive)
- [ ] Test with voice agent (verify natural conversation pacing)
- [ ] Keep non-streaming path for batch jobs
