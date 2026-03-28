path = 'third_party/audioplayers_android/android/build.gradle'
with open(path, encoding='utf-8') as f:
    for idx, line in enumerate(f, 1):
        if 'compileOptions' in line or 'kotlinOptions' in line:
            print(idx, line.strip())
