<?php

/**
 * The SoapClient class provides a client for SOAP 1.1, SOAP 1.2 servers. It can be used in WSDL
 * or non-WSDL mode.
 */
class SoapClient
{
    /**
     * SoapClient constructor
     * @param string|null $wsdl URI of the WSDL file or NULL if working in non-WSDL mode. During development, WSDL caching may be disabled by the use of the soap.wsdl_cache_ttl php.ini setting otherwise changes made to the WSDL file will have no effect until soap.wsdl_cache_ttl is expired.
     * @param array $options [optional] An array of options. If working in WSDL mode, this parameter is optional. If working in non-WSDL mode, the location and uri options must be set, where location is the URL of the SOAP server to send the request to, and uri is the target namespace of the SOAP service. ...
     * @since 5.0
     * @removed 8.0
     */
    public function SoapClient($wsdl, array $options = null) {}

    /**
     * SoapClient constructor
     * @param string|null $wsdl URI of the WSDL file or NULL if working in non-WSDL mode. During development, WSDL caching may be disabled by the use of the soap.wsdl_cache_ttl php.ini setting otherwise changes made to the WSDL file will have no effect until soap.wsdl_cache_ttl is expired.
     * @param array $options [optional] An array of options. If working in WSDL mode, this parameter is optional. If working in non-WSDL mode, the location and uri options must be set, where location is the URL of the SOAP server to send the request to, and uri is the target namespace of the SOAP service. ...
     * @throws SoapFault A SoapFault exception will be thrown if the wsdl URI cannot be loaded.
     * @since 5.0
     */
    public function __construct(
        string|null $wsdl,
        array $options = []
    ) {}

    /**
     * Calls a SOAP function (deprecated)
     *
     * Calling this method directly is deprecated. Usually, SOAP functions can be called as methods
     * of the SoapClient object; in situations where this is not possible or additional options are
     * needed, use SoapClient::__soapCall.
     * @param string $name The name of the SOAP function to call.
     * @param array $args An array of the arguments to pass to the function. This can be either an ordered or an associative array. Note that most SOAP servers require parameter names to be provided, in which case this must be an associative array.
     * @return mixed SOAP functions may return one, or multiple values. If only one value is returned by the SOAP function, the return value will be a scalar. If multiple values are returned, an associative array of named output parameters is returned instead. On error, if the SoapClient object was ...
     * @since 5.0
     * @deprecated
     */
    public function __call(
        string $name,
        array $args
    ): mixed {}

    /**
     * Calls a SOAP function
     * @param string $name The name of the SOAP function to call.
     * @param array $args An array of the arguments to pass to the function. This can be either an ordered or an associative array. Note that most SOAP servers require parameter names to be provided, in which case this must be an associative array.
     * @param array $options [optional] An associative array of options to pass to the client. The location option is the URL of the remote Web service. The uri option is the target namespace of the SOAP service. The soapaction option is the action to call.
     * @param mixed $inputHeaders [optional] An array of headers to be sent along with the SOAP request.
     * @param array &$outputHeaders [optional] If supplied, this array will be filled with the headers from the SOAP response.
     * @return mixed SOAP functions may return one, or multiple values. If only one value is returned by the SOAP function, the return value of __soapCall will be a simple value (e.g. an integer, a string, etc). If multiple values are returned, __soapCall will return an associative array of named output ...
     * @throws SoapFault A SoapFault exception will be thrown if an error occurs and the SoapClient was constructed with the exceptions option not set, or set to TRUE.
     * @since 5.0
     */
    public function __soapCall(
        string $name,
        array $args,
        array|null $options = null,
        $inputHeaders = null,
        &$outputHeaders = null
    ): mixed {}

    /**
     * Returns last SOAP request
     * @return string|null The last SOAP request, as an XML string.
     * @since 5.0
     */
    public function __getLastRequest(): ?string {}

    /**
     * Returns last SOAP response
     * @return string|null The last SOAP response, as an XML string.
     * @since 5.0
     */
    public function __getLastResponse(): ?string {}

    /**
     * Returns the SOAP headers from the last request
     * @return string|null The last SOAP request headers.
     * @since 5.0
     */
    public function __getLastRequestHeaders(): ?string {}

    /**
     * Returns the SOAP headers from the last response
     * @return string|null The last SOAP response headers.
     * @since 5.0
     */
    public function __getLastResponseHeaders(): ?string {}

    /**
     * Returns list of available SOAP functions
     * @return array|null The array of SOAP function prototypes, detailing the return type, the function name and type-hinted parameters.
     * @since 5.0
     */
    public function __getFunctions(): ?array {}

    /**
     * Returns a list of SOAP types
     * @return array|null The array of SOAP types, detailing all structures and types.
     * @since 5.0
     */
    public function __getTypes(): ?array {}

    /**
     * Returns a list of all cookies
     * @return array The array of all cookies
     * @since 5.4
     */
    public function __getCookies(): array {}

    /**
     * Performs a SOAP request
     * @param string $request The XML SOAP request.
     * @param string $location The URL to request.
     * @param string $action The SOAP action.
     * @param int $version The SOAP version.
     * @param bool|int $oneWay [optional] If $oneWay is set to 1, this method returns nothing. Use this where a response is not expected.
     * @param string|null $uriParserClass The classname to use for parsing the redirection URI when a "Location" header is received in the response, or null to use the default, parse_url based parsing.
     * @return string|null The XML SOAP response.
     * @since 5.0
     */
    public function __doRequest(
        string $request,
        string $location,
        string $action,
        int $version,
        bool $oneWay = false
    ): ?string {}

    /**
     * The __setCookie purpose
     * @param string $name The name of the cookie.
     * @param string $value [optional] The value of the cookie. If not specified, the cookie will be deleted.
     * @return void No value is returned.
     * @since 5.0
     */
    public function __setCookie(
        string $name,
        string|null $value = null
    ): void {}

    /**
     * Sets the location of the Web service to use
     * @param string $location [optional] The new endpoint URL.
     * @return string|null The old endpoint URL.
     * @since 5.0
     */
    public function __setLocation(string|null $location = null): ?string {}

    /**
     * Sets SOAP headers for subsequent calls
     * @param mixed $headers The headers to be set. It could be SoapHeader object or array of SoapHeader objects. If not specified or set to NULL, the headers will be deleted.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.0
     */
    public function __setSoapHeaders(
        $headers = null
    ): bool {}
}
