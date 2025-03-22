import sam_sync_test_upstream
import glob

def lambda_handler(event, context):
    import sys
    print(sys.path)
    print(glob.glob("/var/task/*"))
    print(event)
    print("Hello? Goodbye?!")
    sam_sync_test_upstream.my_function("Hello from upstream module")
    return "Hello from Lambda! (modified)"
