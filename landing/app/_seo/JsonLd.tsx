// 구조화된 데이터(JSON-LD)를 <script>로 렌더링하는 서버 컴포넌트.
// 검색엔진/AI 크롤러가 페이지 의미를 구조적으로 이해하도록 돕는다.
export function JsonLd({ data }: { data: object }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }}
    />
  );
}
