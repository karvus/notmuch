#!/usr/bin/env bash
test_description='"notmuch count" for messages and threads'
. $(dirname "$0")/test-lib.sh || exit 1

add_email_corpus

# Note: The 'wc -l' results below are wrapped in arithmetic evaluation
# $((...)) to strip whitespace. This is for portability, as 'wc -l'
# emits whitespace on some BSD variants.

test_begin_subtest "message count is the default for notmuch count"
test_expect_equal \
    "$((`notmuch search --output=messages '*' | wc -l`))" \
    "`notmuch count '*'`"

test_begin_subtest "message count with --output=messages"
test_expect_equal \
    "$((`notmuch search --output=messages '*' | wc -l`))" \
    "`notmuch count --output=messages '*'`"

test_begin_subtest "thread count with --output=threads"
test_expect_equal \
    "$((`notmuch search --output=threads '*' | wc -l`))" \
    "`notmuch count --output=threads '*'`"

test_begin_subtest "thread count is the default for notmuch search"
test_expect_equal \
    "$((`notmuch search '*' | wc -l`))" \
    "`notmuch count --output=threads '*'`"

test_begin_subtest "files count"
test_expect_equal \
    "$((`notmuch search --output=files '*' | wc -l`))" \
    "`notmuch count --output=files '*'`"

test_begin_subtest "files count for a duplicate message-id"
test_expect_equal \
    "2" \
    "`notmuch count --output=files id:20091117232137.GA7669@griffis1.net`"

test_begin_subtest "count with no matching messages"
test_expect_equal \
    "0" \
    "`notmuch count --output=messages from:cworth and not from:cworth`"

test_begin_subtest "count with no matching threads"
test_expect_equal \
    "0" \
    "`notmuch count --output=threads from:cworth and not from:cworth`"

test_begin_subtest "message count is the default for batch count"
notmuch count --batch >OUTPUT <<EOF

from:cworth
EOF
notmuch count --output=messages >EXPECTED
notmuch count --output=messages from:cworth >>EXPECTED
test_expect_equal_file EXPECTED OUTPUT

test_begin_subtest "batch message count"
notmuch count --batch --output=messages >OUTPUT <<EOF
from:cworth

tag:inbox
EOF
notmuch count --output=messages from:cworth >EXPECTED
notmuch count --output=messages >>EXPECTED
notmuch count --output=messages tag:inbox >>EXPECTED
test_expect_equal_file EXPECTED OUTPUT

test_begin_subtest "batch thread count"
notmuch count --batch --output=threads >OUTPUT <<EOF

from:cworth
from:cworth and not from:cworth
foo
EOF
notmuch count --output=threads >EXPECTED
notmuch count --output=threads from:cworth >>EXPECTED
notmuch count --output=threads from:cworth and not from:cworth >>EXPECTED
notmuch count --output=threads foo >>EXPECTED
test_expect_equal_file EXPECTED OUTPUT

test_begin_subtest "batch message count with input file"
cat >INPUT <<EOF
from:cworth

tag:inbox
EOF
notmuch count --input=INPUT --output=messages >OUTPUT
notmuch count --output=messages from:cworth >EXPECTED
notmuch count --output=messages >>EXPECTED
notmuch count --output=messages tag:inbox >>EXPECTED
test_expect_equal_file EXPECTED OUTPUT

backup_database
test_begin_subtest "error message for database open"
target=(${MAIL_DIR}/.notmuch/xapian/postlist.*)
dd if=/dev/zero of="$target" count=3
notmuch count '*' 2>OUTPUT 1>/dev/null
output=$(sed 's/^\(A Xapian exception [^:]*\):.*$/\1/' OUTPUT)
test_expect_equal "${output}" "A Xapian exception occurred opening database"
restore_database

make_shim qsm-shim<<EOF
#include <notmuch-test.h>

WRAP_DLFUNC (notmuch_status_t, notmuch_query_search_messages, (notmuch_query_t *query, notmuch_messages_t **messages))

  /* XXX WARNING THIS CORRUPTS THE DATABASE */
  int fd = open ("target_postlist", O_WRONLY|O_TRUNC);
  if (fd < 0)
    exit (8);
  close (fd);

  return notmuch_query_search_messages_orig(query, messages);
}
EOF

backup_database
test_begin_subtest "error message from query_search_messages"
ln -s ${MAIL_DIR}/.notmuch/xapian/postlist.* target_postlist
notmuch_with_shim qsm-shim count --output=files '*' 2>OUTPUT 1>/dev/null
cat <<EOF > EXPECTED
notmuch count: A Xapian exception occurred
A Xapian exception occurred performing query
Query string was: *
EOF
sed 's/^\(A Xapian exception [^:]*\):.*$/\1/' < OUTPUT > OUTPUT.clean
test_expect_equal_file EXPECTED OUTPUT.clean
restore_database

test_begin_subtest "count library function is non-destructive"
cat<<EOF > EXPECTED
== stdout ==
1: 52 messages
2: 52 messages
Exclude 'spam'
3: 52 messages
4: 52 messages
== stderr ==
EOF

test_C ${MAIL_DIR} <<'EOF' > OUTPUT
#include <notmuch-test.h>

int main (int argc, char** argv)
{
   notmuch_database_t *db;
   notmuch_status_t stat = NOTMUCH_STATUS_SUCCESS;
   char *msg = NULL;
   notmuch_query_t *query;
   const char *str = "tag:inbox or tag:spam";
   const char *tag_str = "spam";
   unsigned int count;

   stat=notmuch_database_open_with_config (argv[1],
				       NOTMUCH_DATABASE_MODE_READ_ONLY,
				       NULL, NULL, &db, &msg);
   if (stat) {
       fprintf (stderr, "open: %s\n", msg);
       exit(1);
   }

   EXPECT0(notmuch_query_create_with_syntax (db, str,
					     NOTMUCH_QUERY_SYNTAX_XAPIAN, &query));
   EXPECT0(notmuch_query_count_messages (query, &count));
   printf("1: %d messages\n", count);
   EXPECT0(notmuch_query_count_messages (query, &count));
   printf("2: %d messages\n", count);
   printf("Exclude '%s'\n",tag_str);
   stat = notmuch_query_add_tag_exclude (query, tag_str);
   if (stat && stat != NOTMUCH_STATUS_IGNORED) {
     fprintf(stderr, "status=%d\n", stat);
     exit(1);
   }
   EXPECT0(notmuch_query_count_messages (query, &count));
   printf("3: %d messages\n", count);
   EXPECT0(notmuch_query_count_messages (query, &count));
   printf("4: %d messages\n", count);
}
EOF
test_expect_equal_file EXPECTED OUTPUT

if [ "${NOTMUCH_HAVE_SFSEXP-0}" = "1" ]; then

    test_begin_subtest "and of exact terms (query=sexp)"
    output=$(notmuch count --query=sexp '(and "wonderful" "wizard")')
    test_expect_equal "$output" 1

    test_begin_subtest "or of exact terms (query=sexp)"
    output=$(notmuch count --query=sexp '(or "php" "wizard")')
    test_expect_equal "$output" 2

    test_begin_subtest "starts-with, case-insensitive (query=sexp)"
    output=$(notmuch count --query=sexp '(starts-with FreeB)')
    test_expect_equal "$output" 5

    test_begin_subtest "query that matches no messages (query=sexp)"
    count=$(notmuch count --query=sexp '(and (from keithp) (to keithp))')
    test_expect_equal 0 "$count"

    test_begin_subtest "Compound subquery (query=sexp)"
    output=$(notmuch count --query=sexp '(thread (of (from keithp) (subject Maildir)))')
    test_expect_equal "$output" 7

fi

test_done
