<?php

/**
 * @since 8.6
 */
enum StreamErrorCode implements \UnitEnum
{
    case None;

    case Generic;

    case ReadFailed;

    case WriteFailed;

    case SeekFailed;

    case SeekNotSupported;

    case FlushFailed;

    case TruncateFailed;

    case ConnectFailed;

    case BindFailed;

    case ListenFailed;

    case AcceptFailed;

    case NotWritable;

    case NotReadable;

    case Disabled;

    case NotFound;

    case PermissionDenied;

    case AlreadyExists;

    case InvalidPath;

    case PathTooLong;

    case OpenFailed;

    case CreateFailed;

    case DupFailed;

    case UnlinkFailed;

    case RenameFailed;

    case MkdirFailed;

    case RmdirFailed;

    case StatFailed;

    case MetaFailed;

    case ChmodFailed;

    case ChownFailed;

    case CopyFailed;

    case TouchFailed;

    case InvalidMode;

    case InvalidMeta;

    case ModeNotSupported;

    case Readonly;

    case RecursionDetected;

    case NotImplemented;

    case NoOpener;

    case PersistentNotSupported;

    case WrapperNotFound;

    case WrapperDisabled;

    case ProtocolUnsupported;

    case WrapperRegistrationFailed;

    case WrapperUnregistrationFailed;

    case WrapperRestorationFailed;

    case FilterNotFound;

    case FilterFailed;

    case CastFailed;

    case CastNotSupported;

    case MakeSeekableFailed;

    case BufferedDataLost;

    case NetworkSendFailed;

    case NetworkRecvFailed;

    case SslNotSupported;

    case ResumptionFailed;

    case SocketPathTooLong;

    case OobNotSupported;

    case ProtocolError;

    case InvalidUrl;

    case InvalidResponse;

    case InvalidHeader;

    case InvalidParam;

    case RedirectLimit;

    case AuthFailed;

    case TimeOut;

    case ArchivingFailed;

    case EncodingFailed;

    case DecodingFailed;

    case InvalidFormat;

    case AllocationFailed;

    case TemporaryFileFailed;

    case LockFailed;

    case LockNotSupported;

    case UserspaceNotImplemented;

    case UserspaceInvalidReturn;

    case UserspaceCallFailed;
}
