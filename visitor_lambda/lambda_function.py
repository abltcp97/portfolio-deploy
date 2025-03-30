import boto3
import os

TABLE_NAME = os.environ['TABLE_NAME']
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    # Gets current # of vistors
    response = table.get_item(Key={'id':'visitor-counter'})
    current = response.get('Item',{}).get('visits', 0)

    #Increment the count and update
    new_count = current + 1
    table.put_item(Item={'id': 'visitor-counter', 'visits': new_count})

    # API gateway expects this format of response and we return the new visitor count
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'applications/json'},
        'body': str(new_count)
    }