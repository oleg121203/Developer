import torch
from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

# Загрузка модели и токенизатора
model_name = "Qwen2.5-Coder-1.5B"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForSeq2SeqLM.from_pretrained(model_name)

def run_model(input_text):
    input_ids = tokenizer.encode(input_text, return_tensors="pt")
    output = model.generate(input_ids, max_length=512)
    return tokenizer.decode(output[0], skip_special_tokens=True)

if __name__ == "__main__":
    with open("/workspace/auto_saved_code.py", "r") as f:
        code = f.read()
    result = run_model(code)
    print(result)
