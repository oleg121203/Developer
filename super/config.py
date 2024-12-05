models = ['Mixtral 8x7B', 'Qwen2.5', 'Coder 1.5B']

answers = {
    "AI Libraries": {
        "Mixtral 8x7B": {"answer": "Для створення програми слід використовувати бібліотеку «Mixtral», оскільки вона має дуже швидку роботу та ефективне використання ресурсів."},
        "Qwen2.5": {"answer": "Для створення програми слід використовувати бібліотеку «Qwen», оскільки вона має дуже добре спроєктовану архітектуру та високий рівень безпеки."},
        "Coder 1.5B": {"answer": "Для створення програми слід використовувати бібліотеку «Coder», оскільки вона має дуже добре підтримку багатьох мов програмування."}
    },
    "Telethon": {
        "Mixtral 8x7B": {"answer": "Telethon превосходит другие библиотеки благодаря асинхронности, полной поддержке MTProto и высокой производительности."},
        "Qwen2.5": {"answer": "Python-telegram-bot предпочтительнее Telethon из-за более простого API и лучшей документации."},
        "Coder 1.5B": {"answer": "Telethon - лучший выбор благодаря его гибкости и поддержке всех функций Telegram, включая пользовательские аккаунты."}
    }
}

questions = {
    "AI Libraries": {
        "Mixtral 8x7B": ["Що таке Mixtral?", "Які переваги має Mixtral?"],
        "Qwen2.5": ["Що таке Qwen?", "Які особливості має Qwen?"],
        "Coder 1.5B": ["Що таке Coder?", "Які можливості має Coder?"]
    }
}

debate_settings = {
    "speeds": {
        "slow": "Повільний темп з детальним обговоренням",
        "medium": "Середній темп",
        "fast": "Швидкий темп без затримок"
    },
    "response_types": {
        "short": "Короткі відповіді",
        "detailed": "Детальні відповіді з аргументацією"
    },
    "permissions": {
        "model_discussion": "Дозвіл моделям обговорюват�� між собою",
        "question_clarification": "Дозвіл уточнювати питання",
        "user_clarification": "Дозвіл запитувати уточнення у користувача"
    }
}

debate_history = {}  # Для зберігання історії спорів
