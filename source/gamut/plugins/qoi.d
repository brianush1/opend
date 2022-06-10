/**
Bridge FreeImage and QOI codec.

Copyright: Copyright Guillaume Piolat 2022
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)

Note: This library is re-implemented in D from FreeImage documentation (FreeImage3180.pdf).
See the differences in DIFFERENCES.md
*/
module gamut.plugins.qoi;

nothrow @nogc @safe:

import core.stdc.stdlib: malloc, free, realloc;
import core.stdc.string: memcpy;
import gamut.types;
import gamut.bitmap;
import gamut.io;
import gamut.plugin;

version(decodeQOI)
    import gamut.codecs.qoi;
else version(encodeQOI)
    import gamut.codecs.qoi;

Plugin makeQOIPlugin()
{
    Plugin p;
    p.format = "QOI";
    p.extensionList = "qoi";

    // Discussion: https://github.com/phoboslab/qoi/issues/167#issuecomment-1117240154
    p.mimeTypes = "image/qoi";

    version(decodeQOI)
        p.loadProc = &Load_QOI;
    else
        p.loadProc = null;
    version(encodeQOI)
        p.saveProc = &Save_QOI;
    else
        p.saveProc = null;
    p.validateProc = &Validate_QOI;
    return p;
}


version(decodeQOI)
FIBITMAP* Load_QOI(FreeImageIO *io, fi_handle handle, int page, int flags, void *data) @trusted
{
    // Read all available bytes from input
    // PERF: qoi_decode should understand FreeImageIO directly.
    // This is temporary.

    // Find length of input
    if (io.seek(handle, 0, SEEK_END) != 0)
        return null;

    int len = io.tell(handle);

    if (!io.rewind(handle))
        return null;

    ubyte* buf = cast(ubyte*) malloc(len);
    if (buf is null)
        return null;

    int requestedComp = computeRequestedImageComponents(flags);
    if (requestedComp == 0) // error
        return null;
    if (requestedComp == -1)
        requestedComp = 0; // auto

    FIBITMAP* bitmap = null;
    ubyte* decoded;
    qoi_desc desc;

    // read all input at once.
    if (len != io.read(buf, 1, len, handle))
        goto error;
        
    decoded = cast(ubyte*) qoi_decode(buf, len, &desc, requestedComp);
    if (decoded is null)
        goto error;        

    if (desc.width > GAMUT_MAX_IMAGE_WIDTH || desc.height > GAMUT_MAX_IMAGE_HEIGHT)
        goto error2;

    // TODO: support desc.colorspace information

    bitmap = cast(FIBITMAP*) malloc(FIBITMAP.sizeof);
    if (!bitmap) 
        goto error2;

    bitmap._data = decoded;
    bitmap._width = desc.width;
    bitmap._height = desc.height;

    if (desc.channels == 3)
        bitmap._type = ImageType.rgb8;
    else if (desc.channels == 4)
        bitmap._type = ImageType.rgba8;
    else
        goto error3;

    bitmap._pitch = desc.channels * desc.width;
    return bitmap;

    error3:
        free(bitmap);
    
    error2:
        free(decoded);

    error:
        free(buf);
        return null;
}


bool Validate_QOI(FreeImageIO *io, fi_handle handle) @trusted
{
    static immutable ubyte[4] qoiSignature = [0x71, 0x6f, 0x69, 0x66]; // "qoif"
    return fileIsStartingWithSignature(io, handle, qoiSignature);
}

version(encodeQOI)
bool Save_QOI(FreeImageIO *io, FIBITMAP *dib, fi_handle handle, int page, int flags, void *data) @trusted
{
    if (page != 0)
        return false;

    if (!FreeImage_HasPixels(dib))
        return false; // no pixel data


    qoi_desc desc;
    desc.width = dib._width;
    desc.height = dib._height;
    desc.colorspace = QOI_SRGB; // TODO: support other colorspace somehow, or at least fail if not SRGB
        
    switch (dib._type)
    {
        case ImageType.rgb8:  desc.channels = 3; break;
        case ImageType.rgba8: desc.channels = 4; break;
        default: 
            return false; // not supported
    }

    // PERF: remove that intermediate copy, whose sole purpose is being gap-free
    // <temp>
    int len = desc.width * desc.height * desc.channels;
    ubyte* continuous = cast(ubyte*) malloc(len);
    if (!continuous)
        return false;
    scope(exit) free(continuous);
    // removes holes
    for (int y = 0; y < desc.height; ++y)
    {
        ubyte* source = dib._data + y * dib._pitch;
        ubyte* dest   = continuous + y * desc.width * desc.channels;
        int lineBytes = desc.channels * desc.width;
        memcpy(dest, source, lineBytes);
    }
    // </temp>
        
    int qoilen;
    ubyte* encoded = cast(ubyte*) qoi_encode(continuous, &desc, &qoilen);
    if (encoded == null)
        return false;
    scope(exit) free(encoded);

    // Write all output at once. This is rather bad, could be done progressively.
    // PERF: adapt qoi writer to output in our own buffer directly.
    if (qoilen != io.write(encoded, 1, qoilen, handle))
        return false;

    return true;
}
