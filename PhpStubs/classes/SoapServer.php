<?php

/**
 * The SoapServer class provides a server for the SOAP 1.1 and SOAP 1.2 protocols. It can be used with or without a WSDL service description.
 */
class SoapServer
{
    /**
     * SoapServer constructor
     * @param mixed $wsdl To use the SoapServer in WSDL mode, pass the URI of a WSDL file. Otherwise, pass NULL and set the uri option to the target namespace for the server.
     * @param array $options [optional] Allow setting a default SOAP version (soap_version), internal character encoding (encoding), and actor URI (actor). The classmap option can be used to map some WSDL types to PHP classes. This option must be an array with WSDL types as keys and names of PHP classes ...
     * @since 5.0
     */
    public function __construct(
        string|null $wsdl,
        array $options = []
    ) {}

    /**
     * SoapServer constructor
     * @param mixed $wsdl To use the SoapServer in WSDL mode, pass the URI of a WSDL file. Otherwise, pass NULL and set the uri option to the target namespace for the server.
     * @param array $options [optional] Allow setting a default SOAP version (soap_version), internal character encoding (encoding), and actor URI (actor). The classmap option can be used to map some WSDL types to PHP classes. This option must be an array with WSDL types as keys and names of PHP classes ...
     * @since 5.0
     * @removed 8.0
     */
    public function SoapServer($wsdl, array $options = null) {}

    /**
     * Sets SoapServer persistence mode
     * @param int $mode One of the SOAP_PERSISTENCE_XXX constants. SOAP_PERSISTENCE_REQUEST - SoapServer data does not persist between requests. This is the default behavior of any SoapServer object after setClass is called. SOAP_PERSISTENCE_SESSION - SoapServer data persists between requests. This is ...
     * @return void No value is returned.
     * @since 5.1
     */
    public function setPersistence(int $mode): void {}

    /**
     * Sets the class which handles SOAP requests
     * @param string $class The name of the exported class.
     * @param mixed ...$args [optional] These optional parameters will be passed to the default class constructor during object creation.
     * @return void No value is returned.
     * @since 5.0
     */
    public function setClass(
        string $class,
        mixed ...$args
    ): void {}

    /**
     * Sets the object which will be used to handle SOAP requests
     * @param object $object The object to handle the requests.
     * @return void No value is returned.
     */
    public function setObject(object $object): void {}

    /**
     * Adds one or more functions to handle SOAP requests
     * @param mixed $functions To export one function, pass the function name into this parameter as a string. To export several functions, pass an array of function names. To export all the functions, pass a special constant SOAP_FUNCTIONS_ALL. functions must receive all input arguments in the same order ...
     * @return void No value is returned.
     * @since 5.0
     */
    public function addFunction($functions): void {}

    /**
     * Returns list of defined functions
     * @return array An array of the defined functions.
     * @since 5.0
     */
    public function getFunctions(): array {}

    /**
     * Handles a SOAP request
     * @param string $request [optional] The SOAP request. If this argument is omitted, the request is assumed to be in the raw POST data of the HTTP request.
     * @return void No value is returned.
     * @since 5.0
     */
    public function handle(string|null $request = null): void {}

    /**
     * Issue SoapServer fault indicating an error
     * @param string $code The error code to return
     * @param string $string A brief description of the error
     * @param string $actor [optional] A string identifying the actor that caused the fault.
     * @param string $details [optional] More details of the fault
     * @param string $name [optional] The name of the fault. This can be used to select a name from a WSDL file.
     * @param string $lang [optional] since 8.5
     * @return void No value is returned.
     * @since 5.0
     */
    public function fault(
        string $code,
        string $string,
        string $actor = '',
        mixed $details = null,
        string $name = ''
    ): void {}

    /**
     * Add a SOAP header to the response
     * @param SoapHeader $header The header to be returned.
     * @return void No value is returned.
     * @since 5.0
     */
    public function addSoapHeader(SoapHeader $header): void {}

    /**
     * Returns last SOAP response
     *
     * Returns the XML sent in the last SOAP response.
     * @since 8.4
     */
    public function __getLastResponse(): ?string {}
}
