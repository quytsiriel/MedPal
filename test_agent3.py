import google.generativeai as genai
import os
import json
api_key = 'AIzaSyBJA7R6WcpFz79s251efo2WXWZojckeQdE'
genai.configure(api_key=api_key)
model = genai.GenerativeModel('gemini-1.5-flash', generation_config=genai.types.GenerationConfig(temperature=0.0, response_mime_type='application/json'))

for m in genai.list_models():
    print(m.name)
