#!/bin/bash
# bs-abr.sh <stream_name>
# Llamado automáticamente por nginx-rtmp (exec_push) cada vez que algo
# empieza a publicar en rtmp://SERVER/live/<stream_name>
# Genera 3 calidades (720p copy, 480p, 360p) + master.m3u8 con ffmpeg.
# nginx-rtmp mata este proceso automáticamente cuando el publish termina.

STREAM="$1"
OUT="/tmp/hls_abr/$STREAM"
LOG="/var/log/bs-abr/${STREAM}.log"
FPS=30          # Debe coincidir con el FPS configurado en OBS
GOP=$((FPS*2))  # Keyframe cada 2s, igual que hls_time

mkdir -p "$OUT/720p" "$OUT/480p" "$OUT/360p" "$(dirname "$LOG")"
rm -f "$OUT"/master.m3u8 "$OUT"/720p/* "$OUT"/480p/* "$OUT"/360p/* 2>/dev/null

exec ffmpeg -i "rtmp://localhost/live/$STREAM" \
  -map 0:v -map 0:a? -c:v:0 copy -c:a:0 aac -b:a:0 128k \
  -map 0:v -map 0:a? -c:v:1 libx264 -preset ultrafast -tune zerolatency \
    -b:v:1 800k -maxrate:v:1 850k -bufsize:v:1 1200k -s:v:1 854x480 \
    -g $GOP -keyint_min $GOP -sc_threshold 0 -c:a:1 aac -b:a:1 96k \
  -map 0:v -map 0:a? -c:v:2 libx264 -preset ultrafast -tune zerolatency \
    -b:v:2 400k -maxrate:v:2 450k -bufsize:v:2 600k -s:v:2 640x360 \
    -g $GOP -keyint_min $GOP -sc_threshold 0 -c:a:2 aac -b:a:2 64k \
  -f hls -hls_time 2 -hls_list_size 6 \
  -hls_flags delete_segments+independent_segments \
  -master_pl_name master.m3u8 \
  -var_stream_map "v:0,a:0,name:720p v:1,a:1,name:480p v:2,a:2,name:360p" \
  -hls_segment_filename "$OUT/%v/seg_%d.ts" \
  "$OUT/%v/index.m3u8" \
  -loglevel warning >> "$LOG" 2>&1
