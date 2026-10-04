import { Link } from "react-router-dom";

type AfterPostProps = {
  success: boolean;
  postLink: string;
};
export default function AfterPost({ success, postLink }: AfterPostProps) {
  return (
    <section className="mt-12 mx-auto max-w-[1280px]">
      <div className="sm:p-8  py-8 px-1 flex flex-col items-center gap-8 w-full overflow-hidden rounded-md bg-[#555] text-white">
        {success ? (
          <>
            <h3 className="text-center text-xl">פורסם בהצלחה</h3>
            <div className=" sm:p-8 p-1 py-4 flex gap-4">
              <Link className="px-4 py-2  rounded bg-sky-600" to={postLink}>
                עבור להודעה
              </Link>
              <Link className="px-4 py-2  rounded bg-sky-600" to="/">
                עבור לדף הבית
              </Link>
            </div>
          </>
        ) : (
          <>
            <h3 className="text-center text-2xl">לא הצלחנו לפרסם!</h3>
            <Link className="px-4 py-2  rounded bg-sky-500" to="/">
              עבור לדף הבית
            </Link>
          </>
        )}
      </div>
    </section>
  );
}
