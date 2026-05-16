feeder.py  - reads files from /synthea/output/fhir and sends them to a FHIR server
cleaner.py - deletes all Subscription resources from a FHIR server
             example: cleaner.py --types Patient,Encouner