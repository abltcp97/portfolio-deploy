from visitor_lambda.lambda_function import get_and_increment_visits

class MockTable:
    def __init__(self, initial_visits):
        self.visits = initial_visits
        self.put_called_with = None

    def get_item(self, Key):
        if self.visits is None:
            return {} #Simulates missing item
        return {"Item":{"visits":self.visits}}
    
    def put_item(self,Item):
        self.put_called_with = Item
        self.visits = Item["Visits"]

    def test_get_and_increment_visits_from_zero():
        table = MockTable(None)
        result = get_and_increment_visits(table)
        assert result == 1
        assert table.put_called_with == {"id":"visitor-counter", "visits": 1}