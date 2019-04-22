FROM alpine:3.12 AS builder

RUN apk add --no-progress --no-cache \
    cmake=3.17.2-r0 \
    yasm=1.3.0-r2 \
    samurai=1.1-r0 \
    gcc=9.3.0-r2 \
    g++=9.3.0-r2

WORKDIR /build
COPY Source Source/
COPY third_party third_party/
COPY CMakeLists.txt CMakeLists.txt

ENV CFLAGS="-static" LDFLAGS="-static -static-libgcc"
RUN cmake -B Build/Release -GNinja -DBUILD_DEC=OFF -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF && cmake --build Build/Release

FROM scratch
LABEL maintainer="Christopher Degawa <ccom@randomderp.com>" \
    name="SVT-AV1" \
    description="SVT-AV1 encoder" \
    vcs-url="https://github.com/OpenVisualCloud/SVT-AV1" \
    License="BSD-2-Clause-Patent" \
    version="0.0.1"
COPY --from=builder /build/Bin/Release/SvtAv1EncApp /
ENTRYPOINT [ "/SvtAv1EncApp" ]
CMD [ "-help" ]
# Example: ffmpeg -i Bin/akiyo_cif.y4m -nostdin -f yuv4mpegpipe -pix_fmt yuv420p - | docker run -i 1480c1/svt-av1 -i stdin -b stdout > test.ivf
# docker run -i 1480c1/svt-av1 -i stdin -b stdout < akiyo_cif.y4m  > test.ivf
