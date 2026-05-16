import json
import uuid
import random
from pathlib import Path

OUTPUT_DIR = Path(__file__).parent.parent / "synthea" / "output" / "patient"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

OTHER_SURNAMES = [
    "Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Wilson","Taylor",
    "Anderson","Thomas","Jackson","White","Harris","Martin","Thompson","Moore","Young","Allen",
    "King","Wright","Scott","Green","Baker","Adams","Nelson","Carter","Mitchell","Roberts",
    "Turner","Phillips","Campbell","Parker","Evans","Edwards","Collins","Stewart","Morris","Rogers",
    "Reed","Cook","Morgan","Bell","Murphy","Bailey","Rivera","Cooper","Richardson","Cox",
    "Howard","Ward","Torres","Peterson","Gray","Ramirez","James","Watson","Brooks","Kelly",
    "Sanders","Price","Bennett","Wood","Barnes","Ross","Henderson","Coleman","Jenkins","Perry",
    "Powell","Long","Patterson","Hughes","Flores","Washington","Butler","Simmons","Foster","Gonzales",
    "Bryant","Alexander","Russell","Griffin","Diaz","Hayes","Myers","Ford","Hamilton","Graham",
    "Sullivan","Wallace","Woods","Cole","West","Jordan","Owens","Reynolds","Fisher","Ellis",
]

FIRST_NAMES_M = [
    "James","John","Robert","Michael","William","David","Richard","Joseph","Thomas","Charles",
    "Christopher","Daniel","Matthew","Anthony","Mark","Donald","Steven","Paul","Andrew","Joshua",
    "Kenneth","Kevin","Brian","George","Timothy","Ronald","Edward","Jason","Jeffrey","Ryan",
]
FIRST_NAMES_F = [
    "Mary","Patricia","Jennifer","Linda","Barbara","Elizabeth","Susan","Jessica","Sarah","Karen",
    "Lisa","Nancy","Betty","Margaret","Sandra","Ashley","Dorothy","Kimberly","Emily","Donna",
    "Michelle","Carol","Amanda","Melissa","Deborah","Stephanie","Rebecca","Sharon","Laura","Cynthia",
]

CITIES = ["Boston", "Springfield", "Worcester", "Cambridge", "Lowell", "Brockton", "Quincy", "Lynn", "Newton", "Somerville"]


def make_patient(family: str) -> dict:
    pid = str(uuid.uuid4())
    ident = str(uuid.uuid4())
    gender = random.choice(["male", "female"])
    first = random.choice(FIRST_NAMES_M if gender == "male" else FIRST_NAMES_F)
    bd = f"{random.randint(1940, 2005)}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
    return {
        "resourceType": "Patient",
        "id": pid,
        "identifier": [
            {
                "system": "https://github.com/synthetichealth/synthea",
                "value": ident,
            },
            {
                "type": {
                    "coding": [
                        {
                            "system": "http://terminology.hl7.org/CodeSystem/v2-0203",
                            "code": "MR",
                            "display": "Medical Record Number",
                        }
                    ],
                    "text": "Medical Record Number",
                },
                "system": "http://hospital.smarthealthit.org",
                "value": ident,
            },
        ],
        "name": [{"use": "official", "family": family, "given": [first]}],
        "gender": gender,
        "birthDate": bd,
        "address": [
            {
                "use": "home",
                "line": [f"{random.randint(1, 999)} {random.choice(['Main','Oak','Maple','Pine','Cedar','Elm'])} St"],
                "city": random.choice(CITIES),
                "state": "Massachusetts",
                "postalCode": f"{random.randint(10000, 99999)}",
                "country": "US",
            }
        ],
    }


patients = (
    [make_patient("Carroll") for _ in range(250)]
    + [make_patient(random.choice(OTHER_SURNAMES)) for _ in range(250)]
)
random.shuffle(patients)

for p in patients:
    out_path = OUTPUT_DIR / f"Patient-{p['id']}.json"
    out_path.write_text(json.dumps(p, indent=2, ensure_ascii=False), encoding="utf-8")

carroll_count = sum(1 for p in patients if p["name"][0]["family"] == "Carroll")
print(f"Generated {len(patients)} patient files in {OUTPUT_DIR}")
print(f"  Carroll : {carroll_count}")
print(f"  Other   : {len(patients) - carroll_count}")
