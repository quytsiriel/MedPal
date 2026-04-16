import json
import os

FHIR_DIR = "data/fhir"
OUTPUT = "data/output/output.txt"

data = []

for file in os.listdir(FHIR_DIR):
    if not file.endswith(".json"):
        continue

    path = os.path.join(FHIR_DIR, file)

    with open(path, encoding="utf-8") as f:
        bundle = json.load(f)

    patient_info = ""
    conditions = []
    observations = []

    for entry in bundle.get("entry", []):
        resource = entry.get("resource", {})
        rtype = resource.get("resourceType")

        # Patient
        if rtype == "Patient":
            gender = resource.get("gender", "")
            birth = resource.get("birthDate", "")

            patient_info = f"Gender: {gender}, Birth: {birth}"

        # Condition
        elif rtype == "Condition":
            try:
                desc = resource["code"]["text"]
                conditions.append(desc)
            except:
                pass

        # 🩺 Observation
        elif rtype == "Observation":
            try:
                desc = resource["code"]["text"]
                observations.append(desc)
            except:
                pass

    text = f"""
    Patient Info: {patient_info}

    Conditions:
    {", ".join(conditions)}

    Symptoms:
    {", ".join(observations)}
    """

    data.append(text)

with open(OUTPUT, "w", encoding="utf-8") as f:
    f.write("\n\n".join(data))

print("Done convert FHIR → text")