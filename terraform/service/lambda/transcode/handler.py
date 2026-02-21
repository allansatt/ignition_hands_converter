# Lambda entry point for transcode job (SQS message = EventBridge S3 object-created event).
# Full implementation is in task "Implement the transcode Lambda": read key from event, get from S3,
# convert_ignition_to_open_hh, write to S3, update DynamoDB, delete message / allow retry.

def lambda_handler(event, context):
    # Stub: real logic in transcode Lambda implementation task.
    for record in event.get("Records", []):
        pass  # TODO: parse body, get S3 key, load object, convert, write, update DynamoDB
    return {"statusCode": 200}
