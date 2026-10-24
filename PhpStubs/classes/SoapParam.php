<?php

/**
 * Represents parameter to a SOAP call.
 */
class SoapParam
{
    /**
     * @var string
     * @since 8.1
     */
    public string $param_name;

    /**
     * @var mixed
     * @since 8.1
     */
    public mixed $param_data;

    /**
     * SoapParam constructor
     * @param mixed $data The data to pass or return. This parameter can be passed directly as PHP value, but in this case it will be named as paramN and the SOAP service may not understand it.
     * @param string $name The parameter name.
     * @since 5.0
     */
    public function __construct(
        mixed $data,
        string $name
    ) {}

    /**
     * SoapParam constructor
     * @param mixed $data The data to pass or return. This parameter can be passed directly as PHP value, but in this case it will be named as paramN and the SOAP service may not understand it.
     * @param string $name The parameter name.
     * @since 5.0
     * @removed 8.0
     */
    public function SoapParam($data, $name) {}
}
