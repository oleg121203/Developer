

import requests
import json


class OllamaModel:
    def __init__(self, api_base="http://172.17.0.1:11434", model="qwen2.5-coder:1.5b"):
        self.api_base = api_base
        self.model = model
        self.completion_options = {
            "temperature": 0.7,
            "max_tokens": 1024,
            "top_p": 0.9,
            "top_k": 30
        }

    def run_model(self, input_text):
        endpoint = f"{self.api_base}/api/generate"
        payload = {
            "model": self.model,
            "prompt": input_text,
            **self.completion_options
        }

        try:
            response = requests.post(endpoint, json=payload)
            response.raise_for_status()
            return response.json()['response']
        except requests.exceptions.RequestException as e:
            print(f"Error calling Ollama API: {e}")
            return None


if __name__ == "__main__":
    model = OllamaModel()
    with open("/workspace/auto_saved_code.py", "r") as f:
        code = f.read()
    result = model.run_model(code)
    if result:
        print(result)
