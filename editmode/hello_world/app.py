import sam_sync_test_upstream

def lambda_handler(event, context):
    print(event)
    sam_sync_test_upstream.my_function("Hello from upstream module")
    return "Hello from Lambda!"
