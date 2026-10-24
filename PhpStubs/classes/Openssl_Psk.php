<?php
namespace Openssl;

/**
 * @since 8.6
 */
final class Psk
{
    public const MAX_PSK_LEN = 256;

    public const MAX_IDENTITY_LEN = 128;

    public readonly string $psk;

    public readonly ?string $identity;

    public function __construct(string $psk, ?string $identity = null) {}
}
