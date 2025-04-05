import requests

def lambda_handler(event, context):
    print(event)
    print(dir(requests))
    return "Hello from Foo Bar lambda!"
