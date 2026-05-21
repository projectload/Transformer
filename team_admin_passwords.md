# كلمات مرور أدمن الفرق (قراءة فقط)

> ⚠️ ملف حسّاس — يحتوي كلمات مرور بنص صريح. لا تشاركه ولا ترفعه لأي مكان عام.
> هذه كلمات **الأدمن (قراءة وعرض فقط)** لكل فريق. كلمات مرور الأعضاء غير مذكورة هنا (مشفّرة في قاعدة البيانات).

| الفريق | كلمة مرور الأدمن (قراءة فقط) |
|---|---|
| Ibri | ibriadmin |
| Wadi Alain | wadiadmin |
| Araqi | araqiadmin |
| Hijermat | hijermatadmin |
| Dank | dankadmin |
| Yanqul | yanquladmin |
| Hamra AlDaroo | hamraadmin |
| Masrooq | masrooqadmin |

## ملاحظات

- صلاحية هذا الحساب: **قراءة وعرض فقط** — لا إضافة ولا تعديل ولا حذف.
- تُخزّن هذه الكلمات مشفّرة (bcrypt) في عمود `viewer_password_hash` بجدول `team_auth` في Supabase.
- للدخول: اختر الفريق في شاشة الدخول واكتب كلمة مرور الأدمن أعلاه → يفتح في وضع 👁️ قراءة فقط.

## تغيير / استرجاع كلمة أدمن أي فريق

شغّل في Supabase → SQL Editor (عدّل الكلمة واسم الفريق):

```sql
UPDATE public.team_auth
SET viewer_password_hash = extensions.crypt('الكلمة_الجديدة', extensions.gen_salt('bf'))
WHERE team_name = 'اسم_الفريق';
```

للتأكد (يجب أن يرجع `viewer`):

```sql
SELECT public.verify_team_role('اسم_الفريق', 'الكلمة_الجديدة');
```

> يجب أن يطبع `UPDATE 1`؛ لو طبع `UPDATE 0` فاسم الفريق غير مطابق. أسماء الفرق الصحيحة:
> `Ibri` · `Wadi Alain` · `Araqi` · `Hijermat` · `Dank` · `Yanqul` · `Hamra AlDaroo` · `Masrooq`

_آخر تحديث: 2026-05-21_
