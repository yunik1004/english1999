# Transcription Scripts

웹사이트에서 대사와 나레이션을 추출하고 한국어 번역을 매칭하는 스크립트입니다.

## 주요 스크립트: `extract_all.py` ⭐

**모든 기능을 포함한 통합 스크립트입니다:**
- 웹에서 자동 fetch
- 나레이션 + 대사 추출
- 영어/한국어 자동 매칭
- JSON 생성

### 설치

```bash
pip install requests beautifulsoup4 lxml
```

### 사용법

```bash
python extract_all.py <chapter_number> -o <output_file>
```

### 예시

```bash
# Chapter 0 (Prologue) 추출
python extract_all.py 0 -o ../assets/data/transcriptions/0_complete.json

# Chapter 1 추출  
python extract_all.py 1 -o ../assets/data/transcriptions/1_complete.json
```

### 출력 형식

```json
{
  "segments": [
    {
      "id": 0,
      "startTime": 0.0,
      "endTime": 3.5,
      "text": "It's raining.",
      "speaker": "",  
      "translation": "비소리가 들려."
    },
    {
      "id": 1,
      "startTime": 3.5,
      "endTime": 6.0,
      "text": "Captain! There is...",
      "speaker": "APPLe",
      "translation": "뒤에 검은 배..."
    }
  ]
}
```

- `speaker`: 빈 문자열("")이면 나레이션, 있으면 대사
- `translation`: 한국어 번역
- `startTime`, `endTime`: placeholder 타임스탬프 (수동 수정 필요)

## 기타 스크립트

### `apply_translations.py`
기존 JSON에 번역만 추가할 때 사용

```bash
python apply_translations.py <input.json> <translations.json> <output.json>
```

### `fetch_and_match.py`
BeautifulSoup 기반 추출 (backup)

## 데이터 소스

- 영어: https://uttu.merui.net/story/en/main/chapter-{N}/transcript
- 한국어: https://uttu.merui.net/story/kr/main/chapter-{N}/transcript

## 타임스탬프 수정

생성된 타임스탬프는 placeholder입니다:
1. YouTube 비디오 시청하며 실제 타이밍 확인
2. JSON의 `startTime`/`endTime` 수동 수정

## 주의사항

- 웹사이트 구조 변경 시 스크립트 수정 필요
- 자동 매칭이 100% 정확하지 않을 수 있음
- 추출 후 내용 검토 권장
