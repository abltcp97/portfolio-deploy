import boto3
import os

def get_and_increment_visits(table):
    # Gets current # of vistors
    response = table.get_item(Key={'id':'visitor-counter'})
    visits = response.get('Item',{}).get('visits', 0) + 1
   

    table.put_item(Item={'id': 'visitor-counter', 'visits': visits})
    return visits

def lambda_handler(event,context):
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(os.environ["TABLE_NAME"])
    new_count = get_and_increment_visits(table)

    # API gateway expects this format of response and we return the new visitor count
    return {
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "https://aalamillo.com",
        "Access-Control-Allow-Methods": "GET",
        "Access-Control-Allow-Headers": "*"
    },
    "body": str(new_count)
}

