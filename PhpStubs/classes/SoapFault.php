<?php

/**
 * Represents a SOAP fault.
 */
class SoapFault extends Exception
{
    /**
     * @var string
     */
    public string|null $faultcode;

    /**
     * @var string
     */
    public string $faultstring;

    /**
     * @var string
     */
    public string|null $faultactor;

    /**
     * @var mixed
     */
    public mixed $detail;

    /**
     * @var string
     */
    public string $faultname;

    /**
     * @var mixed
     */
    public mixed $headerfault;

    /**
     * @var string|null
     * @since 8.1
     */
    public string|null $faultcodens;

    /**
     * @var string|null
     * @since 8.1
     */
    public string|null $_name;

    /**
     * @since 8.5
     */
    public string $lang = "";

    /**
     * SoapFault constructor
     * @param string $code The error code of the SoapFault.
     * @param string $string The error message of the SoapFault.
     * @param string $actor [optional] A string identifying the actor that caused the error.
     * @param mixed $details [optional] More details about the cause of the error.
     * @param string $name [optional] Can be used to select the proper fault encoding from WSDL.
     * @param mixed $headerFault [optional] Can be used during SOAP header handling to report an error in the response header.
     * @param string $lang The human language that the SoapFault is written in. This is only used for SOAP version 1.2.
     * @since 5.0
     */
    public function __construct(
        array|string|null $code,
        string $string,
        string|null $actor = null,
        mixed $details = null,
        string|null $name = null,
        mixed $headerFault = null
    ) {}

    /**
     * SoapFault constructor
     * @param string $faultcode The error code of the SoapFault.
     * @param string $faultstring The error message of the SoapFault.
     * @param string $faultactor [optional] A string identifying the actor that caused the error.
     * @param string $detail [optional] More details about the cause of the error.
     * @param string $faultname [optional] Can be used to select the proper fault encoding from WSDL.
     * @param mixed $headerfault [optional] Can be used during SOAP header handling to report an error in the response header.
     * @since 5.0
     * @removed 8.0
     */
    public function SoapFault($faultcode, $faultstring, $faultactor = null, $detail = null, $faultname = null, $headerfault = null) {}

    /**
     * Obtain a string representation of a SoapFault
     * @return string A string describing the SoapFault.
     * @since 5.0
     */
    public function __toString(): string {}
}
