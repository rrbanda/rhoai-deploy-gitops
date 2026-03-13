FROM docker.io/llamastack/distribution-starter:0.5.2

# Fix Bug 1 (type:"function" leak → Gemini rejects) and
# Bug 2 (strict:null → OpenAI rejects).
# Upstream tracking: Bug 2 partial fix in v0.5.3-dev (730f3b32),
# Bug 1 unfixed on all versions including main.
# Remove this patch once upstream ships both fixes.
RUN STREAMING_PY=$(python3 -c "import llama_stack; import os; print(os.path.join(os.path.dirname(llama_stack.__file__), 'providers/inline/agents/meta_reference/responses/streaming.py'))") && \
    sed -i 's/function=input_tool\.model_dump()/function=input_tool.model_dump(exclude_none=True, exclude={"type"})/' "$STREAMING_PY" && \
    sed -i 's/function=input_tool\.model_dump(exclude_none=True)/function=input_tool.model_dump(exclude_none=True, exclude={"type"})/' "$STREAMING_PY"
