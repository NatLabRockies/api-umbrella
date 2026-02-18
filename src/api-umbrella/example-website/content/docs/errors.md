---
title: General Web Service Errors
generalDocs: true
---

Certain, general errors will be returned in a standardized way from all API Umbrella web services. Additional, service-specific error messages may also be returned (see individual service documentation for those details). The following list describes the general errors any application may return:

<table border="0" cellpadding="0" cellspacing="0" class="doc-parameters table table-bordered">
  <thead class="table-light fs-5">
    <tr>
      <th class="doc-parameters-name" scope="col" style="width: 100px;">Error Code</th>
      <th class="doc-parameters-name" scope="col" style="width: 100px;">HTTP Status Code</th>
      <th class="doc-parameters-required" scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th class="doc-parameter-name" scope="row">API_KEY_MISSING</th>
      <td class="doc-parameter-name">403</td>
      <td class="doc-parameter-description">
        An API key was not supplied. See <a href="/docs/api-key/">API key usage</a> for details on how to pass your API key to the API.
      </td>
    </tr>
    <tr>
      <th class="doc-parameter-name" scope="row">API_KEY_INVALID</th>
      <td class="doc-parameter-name">403</td>
      <td class="doc-parameter-description">
        An invalid API key was supplied. Double check that the API key being passed in is valid, or <a href="/signup/">signup</a> for an API key.
      </td>
    </tr>
    <tr>
      <th class="doc-parameter-name" scope="row">API_KEY_DISABLED</th>
      <td class="doc-parameter-name">403</td>
      <td class="doc-parameter-description">
        The API key supplied has been disabled by an administrator. Please <a href="/contact/">contact us</a> for assistance.
      </td>
    </tr>
    <tr>
      <th class="doc-parameter-name" scope="row">API_KEY_UNAUTHORIZED</th>
      <td class="doc-parameter-name">403</td>
      <td class="doc-parameter-description">
        The API key supplied is not authorized to access the given service. Please <a href="/contact/">contact us</a> for assistance.
      </td>
    </tr>
    <tr>
      <th class="doc-parameter-name" scope="row">API_KEY_UNVERIFIED</th>
      <td class="doc-parameter-name">403</td>
      <td class="doc-parameter-description">
        The API key supplied has not been verified yet. Please check your e-mail to verify the API key. Please <a href="/contact/">contact us</a> for assistance.
      </td>
    </tr>
    <tr>
      <th class="doc-parameter-name" scope="row">HTTPS_REQUIRED</th>
      <td class="doc-parameter-name">400</td>
      <td class="doc-parameter-description">
        Requests to this API must be made over HTTPS. Ensure that the URL being used is over HTTPS.
      </td>
    </tr>
    <tr>
      <th class="doc-parameter-name" scope="row">OVER_RATE_LIMIT</th>
      <td class="doc-parameter-name">429</td>
      <td class="doc-parameter-description">
        The API key has exceeded the rate limits. See <a href="/docs/rate-limits/">rate limits</a> for more details or <a href="/contact/">contact us</a> for assistance.
      </td>
    </tr>
    <tr>
      <th class="doc-parameter-name" scope="row">NOT_FOUND</th>
      <td class="doc-parameter-name">404</td>
      <td class="doc-parameter-description">
        An API could not be found at the given URL. Check your URL.
      </td>
    </tr>
  </tbody>
</table>

## Error Response Body

The error response body will contain an error code value from the table above and a brief description of the error. The descriptions are subject to change, so it's suggested any error handling use the HTTP status code or the error code value for error handling (and not the content of the message description).

### Error Message Response Formats

Depending on the detected format of the request, the error message response may be returned in JSON, XML, CSV, or HTML. Requests of an unknown format will return errors in JSON format.

#### JSON Example

```json
{
  "error": {
    "code": "API_KEY_MISSING",
    "message": "No api_key was supplied. Get one at https://example.com"
  }
}
```

#### XML Example

```xml
<response>
  <error>
    <code>API_KEY_MISSING</code>
    <message>No api_key was supplied. Get one at https://example.com</message>
  </error>
</response>
```

#### CSV Example

```csv
Error Code,Error Message
API_KEY_MISSING,No api_key was supplied. Get one at https://example.com
```

#### HTML Example

```html
<html>
  <body>
    <h1>API_KEY_MISSING</h1>
    <p>No api_key was supplied. Get one at https://example.com</p>
  </body>
</html>
```
