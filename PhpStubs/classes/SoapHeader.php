<?php

/**
 * Represents a SOAP header.
 */
class SoapHeader
{
    /**
     * @var string
     * @since 8.1
     */
    public string $namespace;

    /**
     * @var string
     * @since 8.1
     */
    public string $name;

    /**
     * @var mixed
     * @since 8.1
     */
    public mixed $data;

    /**
     * @var bool
     * @since 8.1
     */
    public bool $mustUnderstand;

    /**
     * @var string|int|null
     * @since 8.1
     */
    public string|int|null $actor;

    /**
     * SoapHeader constructor
     * @param string $namespace The namespace of the SOAP header element.
     * @param string $name The name of the SoapHeader object.
     * @param mixed $data [optional] A SOAP header's content. It can be a PHP value or a SoapVar object.
     * @param bool $mustUnderstand [optional]
     * @param string $actor [optional] Value of the actor attribute of the SOAP header element.
     * @since 5.0
     */
    public function __construct(
        string $namespace,
        string $name,
        mixed $data,
        bool $mustUnderstand = false,
        string|int|null $actor = null
    ) {}

    /**
     * SoapHeader constructor
     * @param string $namespace The namespace of the SOAP header element.
     * @param string $name The name of the SoapHeader object.
     * @param mixed $data [optional] A SOAP header's content. It can be a PHP value or a SoapVar object.
     * @param bool $mustunderstand [optional]
     * @param string $actor [optional] Value of the actor attribute of the SOAP header element.
     * @since 5.0
     * @removed 8.0
     */
    public function SoapHeader($namespace, $name, $data = null, $mustunderstand = false, $actor = null) {}
}
