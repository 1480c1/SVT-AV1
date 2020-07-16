#!/bin/bash

Build_type=Release

die() {
    printf '%s\n' "${@:-Error: Unknown}" >&2
    exit 1
}

run_cmake() (
    build_dir=$1
    shift
    if cmake --help 2>&1 | grep -q -- '-B <path-to-build>'; then
        cmake -B "$PWD/$build_dir" -DCMAKE_BUILD_TYPE=${Build_type:-Debug} \
            -DCMAKE_C_FLAGS_INIT="-fprofile-dir=$PWD/$build_dir -fprofile-generate=$PWD/$build_dir" \
            -DCMAKE_OUTPUT_DIRECTORY="$PWD/$build_dir" \
            -DBUILD_SHARED_LIBS=OFF "$@"
    else
        (
            mkdir "$PWD/$build_dir"
            cd "$PWD/$build_dir"
            cmake .. -DCMAKE_BUILD_TYPE=${Build_type:-Debug} \
                -DCMAKE_C_FLAGS_INIT="-fprofile-dir=$PWD/$build_dir -fprofile-generate=$PWD/$build_dir" \
                -DCMAKE_OUTPUT_DIRECTORY="$PWD/$build_dir" \
                -DBUILD_SHARED_LIBS=OFF "$@"
        ) || return 1
    fi
)

run_cmake_build() (
    build_dir=$1
    mkdir -p build-logs
    shift
    set -- -- "$@"
    if cmake --build 2>&1 | grep -q -- '--parallel'; then
        set -- --parallel $(($(getconf _NPROCESSORS_ONLN 2> /dev/null || sysctl -n hw.ncpu) + 2)) "$@"
    fi
    cmake --build "$PWD/$build_dir" "$@"
)

run_svt() (
    preset=$1 qp=$2 file=$3
    filename=$(basename "$(basename "$file" .y4m)" .yuv)
    mkdir -p "$PWD/build-pr$hash/bitstreams"
    pathname=$PWD/build-pr$hash/bitstreams/svt_M${preset}_${filename}_Q$qp
    lavfi="ssim=stats_file=$PWD/build-pr$hash/bitstreams/svt_M${preset}_${filename}_Q${qp}.ssim"
    lavfi="$lavfi;[0:v][1:v]psnr=stats_file=$PWD/build-pr$hash/bitstreams/svt_M${preset}_${filename}_Q${qp}.psnr"
    lavfi="$lavfi;[0:v][1:v]libvmaf=log_fmt=xml:model_path=$PWD/vmaf_v0.6.1.pkl:log_path=$PWD/build-pr$hash/bitstreams/svt_M${preset}_${filename}_Q${qp}.vmaf"
    shift 3
    cat >> "build-pr$hash/run-svt-m$preset.sh" << EOF
printf 'Running preset: %d qp: %d file %s\n' "$preset" "$qp" "$filename" >&2 && \
            /usr/bin/time --verbose $PWD/build-pr$hash/SvtAv1EncApp  \
                -n 60 --keyint 63 --lookahead 0 --lp 1 \
                --preset "$preset" \
                -q "$qp" \
                -i "$file" \
                -b "$pathname.ivf" $@ > "$pathname.txt" 2>&1 && \
            ffmpeg -threads 40 -i "$PWD/build-pr$hash/bitstreams/svt_M${preset}_${filename}_Q${qp}.ivf" -i "$file" \
                -lavfi "$lavfi" \
                -f null - > "$PWD/build-pr$hash/bitstreams/svt_M${preset}_${filename}_Q${qp}.log" 2>&1
EOF
)

type git > /dev/null 2>&1 || die "Error: failed to find git, cannot run"
type cmake > /dev/null 2>&1 || die "Error: failed to find cmake, cannot run"

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "Error: not in a git repo, cannot run"

test_set=(
    aspen_1080p_60f.y4m
    bqfree_240p_120f.y4m
    blue_sky_360p_120f.y4m
    ducks_take_off_1080p50_60f.y4m
    gipsrestat720p_120f.y4m
    KristenAndSara_1280x720_60_120f.y4m
    MINECRAFT_60f_420.y4m
    Netflix_TunnelFlag_1920x1080_60fps_8bit_420_60f.y4m
    niklas360p_120f.y4m
    red_kayak_360p_120f.y4m
    vidyo1_720p_60fps_120f.y4m
    wikipedia_420.y4m
    boat_hdr_amazon_720p.y4m
    rain2_hdr_amazon_360p.y4m
    water_hdr_amazon_360p.y4m
    flower_garden_422_4sif.y4m
)

if ! [[ -f vmaf_v0.6.1.pkl && -f vmaf_v0.6.1.pkl.model ]]; then
    if type wget > /dev/null 2>&1; then
        wget https://raw.githubusercontent.com/Netflix/vmaf/master/model/vmaf_v0.6.1.pkl \
            https://raw.githubusercontent.com/Netflix/vmaf/master/model/vmaf_v0.6.1.pkl.model
    elif type curl > /dev/null 2>&1; then
        curl -o vmaf_v0.6.1.pkl https://raw.githubusercontent.com/Netflix/vmaf/master/model/vmaf_v0.6.1.pkl
        curl -o vmaf_v0.6.1.pkl.model https://raw.githubusercontent.com/Netflix/vmaf/master/model/vmaf_v0.6.1.pkl.model
    elif type lwp-download > /dev/null 2>&1; then
        lwp-download https://raw.githubusercontent.com/Netflix/vmaf/master/model/vmaf_v0.6.1.pkl vmaf_v0.6.1.pkl
        lwp-download https://raw.githubusercontent.com/Netflix/vmaf/master/model/vmaf_v0.6.1.pkl.model vmaf_v0.6.1.pkl.model
    else
        die "Error: no suitable web downloader available"
    fi
fi

if [ ! -d objective-2-slow ]; then
    if [ ! -f objective-2-slow.tar.gz ]; then
        if type wget > /dev/null 2>&1; then
            wget https://media.xiph.org/video/derf/objective-2-slow.tar.gz
        elif type curl > /dev/null 2>&1; then
            curl -o objective-2-slow.tar.gz https://media.xiph.org/video/derf/objective-2-slow.tar.gz
        elif type lwp-download > /dev/null 2>&1; then
            lwp-download https://media.xiph.org/video/derf/objective-2-slow.tar.gz objective-2-slow.tar.gz
        else
            die "Error: no suitable web downloader available"
        fi
    fi
    tar xf objective-2-slow.tar.gz "${test_set[@]}" || die "Error: failed to un-tar the test set, try deleting objective-2-slow.tar.gz and rerunning"
fi

if [ ! -f objective-2-slow/flower_garden_422_4sif.y4m ]; then
    if type wget > /dev/null 2>&1; then
        wget https://media.xiph.org/video/derf/y4m/flower_garden_422_4sif.y4m
        mv flower_garden_422_4sif.y4m objective-2-slow/flower_garden_422_4sif.y4m
    elif type curl > /dev/null 2>&1; then
        curl -o objective-2-slow/flower_garden_422_4sif.y4m https://media.xiph.org/video/derf/y4m/flower_garden_422_4sif.y4m
    elif type lwp-download > /dev/null 2>&1; then
        lwp-download https://media.xiph.org/video/derf/y4m/flower_garden_422_4sif.y4m objective-2-slow/flower_garden_422_4sif.y4m
    else
        die "Error: no suitable web downloader available"
    fi
fi

hash=$(git rev-parse HEAD)

printf 'Building the pr'
run_cmake "build-pr$hash" || die "Error: Failed to configure the current branch"
run_cmake_build "build-pr$hash"

rm -f "build-pr$hash/"time_enc_*.log

for preset in 8 4 0; do
    printf '' > "build-pr$hash/run-svt-m$preset.sh"
    chmod +x "build-pr$hash/run-svt-m$preset.sh"
    for qp in 63 55 43 32 20; do
        for stream in "${test_set[@]/#/objective-2-slow/}"; do
            case $stream in
            objective-2-slow/street_hdr_amazon_2160p.y4m) continue ;;
            esac
            [[ $stream == *hdr* ]] && args='--enable-hdr 1' || args=''
            run_svt $preset $qp "$stream" $args
        done
    done
done

for preset in 8 4 0; do
    /usr/bin/time --verbose -o "build-pr$hash/time_enc_$preset.log" parallel -j "$(nproc)" < "build-pr$hash/run-svt-m$preset.sh"
done
echo "done"
