import logging
import requests
import json
import time
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)


class CodeChangeHandler(FileSystemEventHandler):
    def __init__(self, model):
        self.model = model
        self.last_modified = {}

    def on_modified(self, event):
        if event.src_path.endswith('.py'):
            current_time = time.time()
            if (event.src_path not in self.last_modified or
                    current_time - self.last_modified[event.src_path] > 3):
                self.last_modified[event.src_path] = current_time
                self.process_file(event.src_path)

    def process_file(self, filepath):
        try:
            with open(filepath, 'r') as f:
                code = f.read()
            logging.info(f"Processing file: {filepath}")
            result = self.model.run_model(f"Refactor this code:\n{code}")
            if result:
                # Create backup with timestamp
                timestamp = time.strftime("%Y%m%d-%H%M%S")
                backup_path = f"{filepath}.{timestamp}.bak"
                Path(filepath).rename(backup_path)
                logging.info(f"Created backup: {backup_path}")

                with open(filepath, 'w') as f:
                    f.write(result)
                logging.info(f"Successfully refactored: {filepath}")
        except Exception as e:
            logging.error(f"Error processing {filepath}: {e}")
            return False
        return True


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
            logging.error(f"Error calling Ollama API: {e}")
            return None

    def start_monitoring(self, path="/workspace"):
        event_handler = CodeChangeHandler(self)
        observer = Observer()
        observer.schedule(event_handler, path, recursive=True)
        observer.start()
        return observer


if __name__ == "__main__":
    model = OllamaModel()
    observer = model.start_monitoring()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
