# W3cTraceContextValidation

This is an app that implements the W3C Trace Context Validation Service:

* https://github.com/w3c/trace-context/tree/master/test

Run the test:

```
docker build -t wc3_validator .
docker run -p 7777:7777 -it wc3_validator python trace-context/test/test.py http://host.docker.internal:4002/test
```
pip3 install aiohttp
python3 test/test.py http://127.0.0.1:4002/test