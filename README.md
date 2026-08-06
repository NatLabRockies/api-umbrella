# API Umbrella

## What Is API Umbrella?

API Umbrella is an open source API management platform for exposing web service APIs. The basic goal of API Umbrella is to make life easier for both API creators and API consumers. How?

* **Make life easier for API creators:** Allow API creators to focus on building APIs.
  * **Standardize the boring stuff:** APIs can assume the boring stuff (access control, rate limiting, analytics, etc.) is already taken care if the API is being accessed, so common functionality doesn't need to be implemented in the API code.
  * **Easy to add:** API Umbrella acts as a layer above your APIs, so your API code doesn't need to be modified to take advantage of the features provided.
  * **Scalability:** Make it easier to scale your APIs.
* **Make life easier for API consumers:** Let API consumers easily explore and use your APIs.
  * **Unify disparate APIs:** Present separate APIs as a cohesive offering to API consumers. APIs running on different servers or written in different programming languages can be exposed at a single endpoint for the API consumer.
  * **Standardize access:** All your APIs are can be accessed using the same API key credentials.
  * **Standardize documentation:** All your APIs are documented in a single place and in a similar fashion.

## Getting Started
Follow the instructions available [here](https://api-umbrella.readthedocs.io/en/latest/getting-started.html#) to download and install API Umbrella. Follow the quick setup instructions on the download page to begin running API Umbrella.

## Features
API Umbrella brings a range of features to simplify the lives of API creators and consumers. The primary features offered by API Umbrella are:

1. [**API Key Management:**](#api-key-management) Handles API key registration, usage, and validation across multiple services without requiring any code changes in the API.

2. [**Rate Limiting:**](#rate-limiting) Prevents abuse by controlling API usage on a per-user basis, ensuring API servers aren't overloaded.

3. [**Analytics & Reporting:**](#analytics--reporting) Provides detailed insights into API usage, performance monitoring, and flexible querying for traffic analysis.

4. [**Additional Security Layer:**](#additional-security-layer) Acts as a proxy layer above APIs to help scale services while managing access control.

5. [**Centralized API Access:**](#centralized-api-access) Offers a unified entry point for developers to manage and maintain multiple APIs across the platform.

6. [**Native Documentation Support:**](#native-documentation-support) Can host or link to API documentation, making it easy for developers to find and understand APIs.

API Umbrella allows developers to focus on building APIs while it automates common tasks like access control, security, logging, and scaling​

### API Key Management
* **API Key Signup:** Provides a streamlined process for users to register and receive API keys.
* **Shared API Keys:** Users can reuse a single API key across all participating APIs in the Umbrella network.
* **No Code Changes:** API providers don’t need to modify their code to accommodate key management as API Umbrella handles this via a transparent layer.
### Rate Limiting
* **Custom Rate Limits:** Helps prevent abuse by allowing admins to set different rate limits per user or per API.
* **Per-User Limits:** Admins can assign varying usage quotas for different users, which ensures balanced API access.
* **Automatic Enforcement:** The rate limiting rules are enforced within the Umbrella layer, removing the need to do so locally.
### **Analytics & Reporting**
* **Usage Monitoring:** Allows for monitoring of API consumption through detailed traffic and performance metric logging.
* **Detailed Stats:** Provides insights into API traffic down to individual users.
* **API Performance Metrics:** Displays API response times in a graphical format.
* **Flexible Data Queries:** Custom queries allow for detailed data breakdowns based on API usage.
### **Additional Security Layer**
* **Access Control:** Provides access control mechanisms to restrict who can access specific APIs based on roles or permissions.
* **IP Whitelisting/Blacklisting:** Can restrict or allow access to APIs based on IP addresses.
* **SSL/TLS Encryption:** Ensures secure communication between clients and the API gateway by enforcing SSL encryption.
### **Centralized API Access**
* **Unified API Gateway:** Simplifies multi-API management by acting as a single access point for all APIs under an Umbrella.
### **Native Documentation Support**
* **API Documentation Hosting:** Hosts or links to API documentation, allowing users to easily explore and learn about various APIs.
* **Interactive Documentation:** API Umbrella supports interactive API documentation, enabling developers to try out APIs directly from the documentation site (integrated via tools like Swagger)​

## API Umbrella Development

Are you interested in working on the code behind API Umbrella? See our [development setup guide](https://api-umbrella.readthedocs.org/en/latest/developer/dev-setup.html) to see how you can get a local development environment setup.

## Who's using API Umbrella?

* [api.data.gov](https://api.data.gov/)
* [NREL Developer Network](http://developer.nrel.gov/)
* [api.sam.gov](https://api.sam.gov)

Are you using API Umbrella? [Edit this file](https://github.com/NREL/api-umbrella/blob/master/README.md) and let us know.

## License

API Umbrella is open sourced under the [MIT license](https://github.com/NREL/api-umbrella/blob/master/LICENSE.txt).
