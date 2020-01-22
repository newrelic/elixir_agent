# W3cTraceContextValidation

This is an app that implements the W3C Trace Context Validation Service:

* https://github.com/w3c/trace-context/tree/master/test

-----

Start the app:

```
env NEW_RELIC_HARVEST_ENABLED=true iex -S mix
```

Run the test:

```
git clone https://github.com/w3c/trace-context.git
cd trace-context
pip3 install aiohttp
python3 test/test.py http://127.0.0.1:4002/test
```
