/* =======================================================================
 * Sched_FileSync_NightlyTest.cls
 * -----------------------------------------------------------------------
 * ▸ Schedules the nightly job and ensures a batch is enqueued
 * ==================================================================== */
@IsTest
private class Sched_FileSync_NightlyTest {

    @IsTest
    static void enqueuesBatch() {

        Test.startTest();

        String jobId = System.schedule('UT-FileSync-Nightly',
                                       '0 15 2 * * ?',
                                       new Sched_FileSync_Nightly());

        Test.stopTest();

        Integer jobs = [SELECT COUNT() FROM AsyncApexJob
                        WHERE  ApexClass.Name = 'FileSyncBatch'
                        AND    JobType = 'BatchApex'];
        System.assert(jobs > 0,
                      'Scheduler must enqueue a FileSyncBatch job');
        System.assertNotEquals(null, jobId,
                               'schedule should return a job id');
    }
}
