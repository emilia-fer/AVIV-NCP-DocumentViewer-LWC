/**
 * Schedules the batch.  Runs every night at 02:15 UTC.
 * Change the CRON if you prefer weekly:
 *   '0 0 3 ? * MON'   // every Monday 03:00 UTC
 */
global with sharing class Sched_FileSync_Nightly
        implements Schedulable {

    global void execute(SchedulableContext sc) {

        // yesterday 00:00 – change to 7 days back if you run weekly
        Date targetDay = Date.today().addDays(-1);  // “yesterday”
        DateTime since = DateTime.newInstanceGmt(
                    targetDay.year(), targetDay.month(), targetDay.day(),
                    0, 0, 0);

        FileSyncBatch b = new FileSyncBatch(since);
        Database.executeBatch(b, 200); // 200 = scopeSize
    }
}