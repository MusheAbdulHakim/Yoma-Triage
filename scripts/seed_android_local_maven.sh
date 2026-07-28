#!/usr/bin/env bash
# Seed android/local-maven with lint jars when dl.google.com times out.
# Copies locally cached 32.0.1 artifacts and publishes them as 31.7.3 (AGP 8.7 expectation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL="$ROOT/mobile/android/local-maven"
CACHE="$HOME/.gradle/caches/modules-2/files-2.1/com.android.tools.external.com-intellij"
IC=$(find "$CACHE/intellij-core" -name 'intellij-core-*.jar' | sort -V | tail -1)
KC=$(find "$CACHE/kotlin-compiler" -name 'kotlin-compiler-*.jar' | sort -V | tail -1)
if [[ -z "$IC" || -z "$KC" ]]; then
  echo "Missing cached lint jars under $CACHE — run any Android Gradle build once first." >&2
  exit 1
fi
rm -rf "$LOCAL"
for art in intellij-core kotlin-compiler; do
  DIR="$LOCAL/com/android/tools/external/com-intellij/$art/31.7.3"
  mkdir -p "$DIR"
  if [[ "$art" == intellij-core ]]; then cp -f "$IC" "$DIR/$art-31.7.3.jar"; else cp -f "$KC" "$DIR/$art-31.7.3.jar"; fi
  cat > "$DIR/$art-31.7.3.pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.android.tools.external.com-intellij</groupId>
  <artifactId>$art</artifactId>
  <version>31.7.3</version>
  <packaging>jar</packaging>
</project>
EOF
done
echo "Seeded $LOCAL"
