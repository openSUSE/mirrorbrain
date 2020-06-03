#!../lib/test-in-container-environs.sh
set -ex

./environ.sh mb9 $(pwd)/mirrorbrain
./environ.sh pg9-system2

pg9*/start.sh

mb9*/configure_db.sh pg9

size=${BIG_FILE_SIZE:-100M}
file=.product/mb/.data/file$size

mkdir -p .product/mb/.data
[ -f $file ] || ! which fallocate || fallocate -l $size $file
[ -f $file ] || dd if=/dev/zero of=./$file bs=4K iflag=fullblock,count_bytes count=$size

mkdir -p mb9/downloads

ln $file mb9/downloads/

sed -i '/dbname = mirrorbrain/a zsync_hashes = 1' mb9*/mirrorbrain.conf

mb9*/mb.sh makehashes -v $PWD/mb9/downloads
pg9*/sql.sh -c "select sha1, zblocksize, zhashlens, length(zsums) from files" mirrorbrain
