namespace :embeddings do
  desc "Embed every meeting that has a summary or transcript (run synchronously, not via the job queue, so the pacing below actually throttles the real Voyage calls)"
  task backfill: :environment do
    scope = Meeting.where.not(summary: nil).or(Meeting.where.not(transcript: nil))
    count = scope.count

    scope.find_each.with_index(1) do |meeting, index|
      EmbedMeetingJob.perform_now(meeting.id)
      puts "#{index}/#{count}: #{meeting.title || meeting.id} (#{meeting.transcript_chunks.count} chunks)"
      sleep(1) # Voyage's rate limit is tight enough to hit on back-to-back requests even with retries
    end
  end
end
