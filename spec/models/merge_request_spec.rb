require 'spec_helper'

describe MergeRequest, models: true do
  include RepoHelpers

  subject { create(:merge_request) }

  describe 'associations' do
    it { is_expected.to belong_to(:target_project).with_foreign_key(:target_project_id).class_name('Project') }
    it { is_expected.to belong_to(:source_project).with_foreign_key(:source_project_id).class_name('Project') }
    it { is_expected.to belong_to(:merge_user).class_name("User") }
    it { is_expected.to have_many(:merge_request_diffs).dependent(:destroy) }
  end

  describe 'modules' do
    subject { described_class }

    it { is_expected.to include_module(InternalId) }
    it { is_expected.to include_module(Issuable) }
    it { is_expected.to include_module(Referable) }
    it { is_expected.to include_module(Sortable) }
    it { is_expected.to include_module(Taskable) }
  end

  describe "act_as_paranoid" do
    it { is_expected.to have_db_column(:deleted_at) }
    it { is_expected.to have_db_index(:deleted_at) }
  end

  describe 'validation' do
    it { is_expected.to validate_presence_of(:target_branch) }
    it { is_expected.to validate_presence_of(:source_branch) }

    context "Validation of merge user with Merge When Build succeeds" do
      it "allows user to be nil when the feature is disabled" do
        expect(subject).to be_valid
      end

      it "is invalid without merge user" do
        subject.merge_when_build_succeeds = true
        expect(subject).not_to be_valid
      end

      it "is valid with merge user" do
        subject.merge_when_build_succeeds = true
        subject.merge_user = build(:user)

        expect(subject).to be_valid
      end
    end
  end

  describe 'respond to' do
    it { is_expected.to respond_to(:unchecked?) }
    it { is_expected.to respond_to(:can_be_merged?) }
    it { is_expected.to respond_to(:cannot_be_merged?) }
    it { is_expected.to respond_to(:merge_params) }
    it { is_expected.to respond_to(:merge_when_build_succeeds) }
  end

  describe '.in_projects' do
    it 'returns the merge requests for a set of projects' do
      expect(described_class.in_projects(Project.all)).to eq([subject])
    end
  end

  describe '#target_branch_sha' do
    let(:project) { create(:project) }

    subject { create(:merge_request, source_project: project, target_project: project) }

    context 'when the target branch does not exist' do
      before do
        project.repository.raw_repository.delete_branch(subject.target_branch)
      end

      it 'returns nil' do
        expect(subject.target_branch_sha).to be_nil
      end
    end

    it 'returns memoized value' do
      subject.target_branch_sha = '8ffb3c15a5475e59ae909384297fede4badcb4c7'

      expect(subject.target_branch_sha).to eq '8ffb3c15a5475e59ae909384297fede4badcb4c7'
    end
  end

  describe '#source_branch_sha' do
    let(:last_branch_commit) { subject.source_project.repository.commit(subject.source_branch) }

    context 'with diffs' do
      subject { create(:merge_request, :with_diffs) }
      it 'returns the sha of the source branch last commit' do
        expect(subject.source_branch_sha).to eq(last_branch_commit.sha)
      end
    end

    context 'without diffs' do
      subject { create(:merge_request, :without_diffs) }
      it 'returns the sha of the source branch last commit' do
        expect(subject.source_branch_sha).to eq(last_branch_commit.sha)
      end
    end

    context 'when the merge request is being created' do
      subject { build(:merge_request, source_branch: nil, compare_commits: []) }
      it 'returns nil' do
        expect(subject.source_branch_sha).to be_nil
      end
    end

    it 'returns memoized value' do
      subject.source_branch_sha = '2e5d3239642f9161dcbbc4b70a211a68e5e45e2b'

      expect(subject.source_branch_sha).to eq '2e5d3239642f9161dcbbc4b70a211a68e5e45e2b'
    end
  end

  describe '#to_reference' do
    it 'returns a String reference to the object' do
      expect(subject.to_reference).to eq "!#{subject.iid}"
    end

    it 'supports a cross-project reference' do
      cross = double('project')
      expect(subject.to_reference(cross)).to eq "#{subject.source_project.to_reference}!#{subject.iid}"
    end
  end

  describe '#raw_diffs' do
    let(:merge_request) { build(:merge_request) }
    let(:options) { { paths: ['a/b', 'b/a', 'c/*'] } }

    context 'when there are MR diffs' do
      it 'delegates to the MR diffs' do
        merge_request.merge_request_diff = MergeRequestDiff.new

        expect(merge_request.merge_request_diff).to receive(:raw_diffs).with(options)

        merge_request.raw_diffs(options)
      end
    end

    context 'when there are no MR diffs' do
      it 'delegates to the compare object' do
        merge_request.compare = double(:compare)

        expect(merge_request.compare).to receive(:raw_diffs).with(options)

        merge_request.raw_diffs(options)
      end
    end
  end

  describe '#diffs' do
    let(:merge_request) { build(:merge_request) }
    let(:options) { { paths: ['a/b', 'b/a', 'c/*'] } }

    context 'when there are MR diffs' do
      it 'delegates to the MR diffs' do
        merge_request.save

        expect(merge_request.merge_request_diff).to receive(:raw_diffs).with(hash_including(options))

        merge_request.diffs(options)
      end
    end

    context 'when there are no MR diffs' do
      it 'delegates to the compare object' do
        merge_request.compare = double(:compare)

        expect(merge_request.compare).to receive(:diffs).with(options)

        merge_request.diffs(options)
      end
    end
  end

  describe "#mr_and_commit_notes" do
    let!(:merge_request) { create(:merge_request) }

    before do
      allow(merge_request).to receive(:commits) { [merge_request.source_project.repository.commit] }
      create(:note_on_commit, commit_id: merge_request.commits.first.id,
                              project: merge_request.project)
      create(:note, noteable: merge_request, project: merge_request.project)
    end

    it "includes notes for commits" do
      expect(merge_request.commits).not_to be_empty
      expect(merge_request.mr_and_commit_notes.count).to eq(2)
    end

    it "includes notes for commits from target project as well" do
      create(:note_on_commit, commit_id: merge_request.commits.first.id,
                              project: merge_request.target_project)

      expect(merge_request.commits).not_to be_empty
      expect(merge_request.mr_and_commit_notes.count).to eq(3)
    end
  end

  describe '#is_being_reassigned?' do
    it 'returns true if the merge_request assignee has changed' do
      subject.assignee = create(:user)
      expect(subject.is_being_reassigned?).to be_truthy
    end
    it 'returns false if the merge request assignee has not changed' do
      expect(subject.is_being_reassigned?).to be_falsey
    end
  end

  describe '#for_fork?' do
    it 'returns true if the merge request is for a fork' do
      subject.source_project = create(:project, namespace: create(:group))
      subject.target_project = create(:project, namespace: create(:group))

      expect(subject.for_fork?).to be_truthy
    end

    it 'returns false if is not for a fork' do
      expect(subject.for_fork?).to be_falsey
    end
  end

  describe 'detection of issues to be closed' do
    let(:issue0) { create :issue, project: subject.project }
    let(:issue1) { create :issue, project: subject.project }

    let(:commit0) { double('commit0', safe_message: "Fixes #{issue0.to_reference}") }
    let(:commit1) { double('commit1', safe_message: "Fixes #{issue0.to_reference}") }
    let(:commit2) { double('commit2', safe_message: "Fixes #{issue1.to_reference}") }

    before do
      subject.project.team << [subject.author, :developer]
      allow(subject).to receive(:commits).and_return([commit0, commit1, commit2])
    end

    it 'accesses the set of issues that will be closed on acceptance' do
      allow(subject.project).to receive(:default_branch).
        and_return(subject.target_branch)

      closed = subject.closes_issues

      expect(closed).to include(issue0, issue1)
    end

    it 'only lists issues as to be closed if it targets the default branch' do
      allow(subject.project).to receive(:default_branch).and_return('master')
      subject.target_branch = 'something-else'

      expect(subject.closes_issues).to be_empty
    end

    it 'detects issues mentioned in the description' do
      issue2 = create(:issue, project: subject.project)
      subject.description = "Closes #{issue2.to_reference}"
      allow(subject.project).to receive(:default_branch).
        and_return(subject.target_branch)

      expect(subject.closes_issues).to include(issue2)
    end
  end

  describe "#work_in_progress?" do
    ['WIP ', 'WIP:', 'WIP: ', '[WIP]', '[WIP] ', ' [WIP] WIP [WIP] WIP: WIP '].each do |wip_prefix|
      it "detects the '#{wip_prefix}' prefix" do
        subject.title = "#{wip_prefix}#{subject.title}"
        expect(subject.work_in_progress?).to eq true
      end
    end

    it "doesn't detect WIP for words starting with WIP" do
      subject.title = "Wipwap #{subject.title}"
      expect(subject.work_in_progress?).to eq false
    end

    it "doesn't detect WIP for words containing with WIP" do
      subject.title = "WupWipwap #{subject.title}"
      expect(subject.work_in_progress?).to eq false
    end

    it "doesn't detect WIP by default" do
      expect(subject.work_in_progress?).to eq false
    end
  end

  describe '#can_remove_source_branch?' do
    let(:user) { create(:user) }
    let(:user2) { create(:user) }

    before do
      subject.source_project.team << [user, :master]

      subject.source_branch = "feature"
      subject.target_branch = "master"
      subject.save!
    end

    it "can't be removed when its a protected branch" do
      allow(subject.source_project).to receive(:protected_branch?).and_return(true)
      expect(subject.can_remove_source_branch?(user)).to be_falsey
    end

    it "can't remove a root ref" do
      subject.source_branch = "master"
      subject.target_branch = "feature"

      expect(subject.can_remove_source_branch?(user)).to be_falsey
    end

    it "is unable to remove the source branch for a project the user cannot push to" do
      expect(subject.can_remove_source_branch?(user2)).to be_falsey
    end

    it "can be removed if the last commit is the head of the source branch" do
      allow(subject).to receive(:source_branch_head).and_return(subject.diff_head_commit)

      expect(subject.can_remove_source_branch?(user)).to be_truthy
    end

    it "cannot be removed if the last commit is not also the head of the source branch" do
      subject.source_branch = "lfs"

      expect(subject.can_remove_source_branch?(user)).to be_falsey
    end
  end

  describe "#reset_merge_when_build_succeeds" do
    let(:merge_if_green) do
      create :merge_request, merge_when_build_succeeds: true, merge_user: create(:user),
                             merge_params: { "should_remove_source_branch" => "1", "commit_message" => "msg" }
    end

    it "sets the item to false" do
      merge_if_green.reset_merge_when_build_succeeds
      merge_if_green.reload

      expect(merge_if_green.merge_when_build_succeeds).to be_falsey
      expect(merge_if_green.merge_params["should_remove_source_branch"]).to be_nil
      expect(merge_if_green.merge_params["commit_message"]).to be_nil
    end
  end

  describe "#hook_attrs" do
    let(:attrs_hash) { subject.hook_attrs.to_h }

    [:source, :target].each do |key|
      describe "#{key} key" do
        include_examples 'project hook data', project_key: key do
          let(:data)    { attrs_hash }
          let(:project) { subject.send("#{key}_project") }
        end
      end
    end

    it "has all the required keys" do
      expect(attrs_hash).to include(:source)
      expect(attrs_hash).to include(:target)
      expect(attrs_hash).to include(:last_commit)
      expect(attrs_hash).to include(:work_in_progress)
    end
  end

  describe '#diverged_commits_count' do
    let(:project)      { create(:project) }
    let(:fork_project) { create(:project, forked_from_project: project) }

    context 'when the target branch does not exist anymore' do
      subject { create(:merge_request, source_project: project, target_project: project) }

      before do
        project.repository.raw_repository.delete_branch(subject.target_branch)
        subject.reload
      end

      it 'does not crash' do
        expect{ subject.diverged_commits_count }.not_to raise_error
      end

      it 'returns 0' do
        expect(subject.diverged_commits_count).to eq(0)
      end
    end

    context 'diverged on same repository' do
      subject(:merge_request_with_divergence) { create(:merge_request, :diverged, source_project: project, target_project: project) }

      it 'counts commits that are on target branch but not on source branch' do
        expect(subject.diverged_commits_count).to eq(5)
      end
    end

    context 'diverged on fork' do
      subject(:merge_request_fork_with_divergence) { create(:merge_request, :diverged, source_project: fork_project, target_project: project) }

      it 'counts commits that are on target branch but not on source branch' do
        expect(subject.diverged_commits_count).to eq(5)
      end
    end

    context 'rebased on fork' do
      subject(:merge_request_rebased) { create(:merge_request, :rebased, source_project: fork_project, target_project: project) }

      it 'counts commits that are on target branch but not on source branch' do
        expect(subject.diverged_commits_count).to eq(0)
      end
    end

    describe 'caching' do
      before(:example) do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      end

      it 'caches the output' do
        expect(subject).to receive(:compute_diverged_commits_count).
          once.
          and_return(2)

        subject.diverged_commits_count
        subject.diverged_commits_count
      end

      it 'invalidates the cache when the source sha changes' do
        expect(subject).to receive(:compute_diverged_commits_count).
          twice.
          and_return(2)

        subject.diverged_commits_count
        allow(subject).to receive(:source_branch_sha).and_return('123abc')
        subject.diverged_commits_count
      end

      it 'invalidates the cache when the target sha changes' do
        expect(subject).to receive(:compute_diverged_commits_count).
          twice.
          and_return(2)

        subject.diverged_commits_count
        allow(subject).to receive(:target_branch_sha).and_return('123abc')
        subject.diverged_commits_count
      end
    end
  end

  it_behaves_like 'an editable mentionable' do
    subject { create(:merge_request) }

    let(:backref_text) { "merge request #{subject.to_reference}" }
    let(:set_mentionable_text) { ->(txt){ subject.description = txt } }
  end

  it_behaves_like 'a Taskable' do
    subject { create :merge_request, :simple }
  end

  describe '#commits_sha' do
    let(:commit0) { double('commit0', sha: 'sha1') }
    let(:commit1) { double('commit1', sha: 'sha2') }
    let(:commit2) { double('commit2', sha: 'sha3') }

    before do
      allow(subject.merge_request_diff).to receive(:commits).and_return([commit0, commit1, commit2])
    end

    it 'returns sha of commits' do
      expect(subject.commits_sha).to contain_exactly('sha1', 'sha2', 'sha3')
    end
  end

  describe '#pipeline' do
    describe 'when the source project exists' do
      it 'returns the latest pipeline' do
        pipeline = double(:ci_pipeline, ref: 'master')

        allow(subject).to receive(:diff_head_sha).and_return('123abc')

        expect(subject.source_project).to receive(:pipeline).
          with('123abc', 'master').
          and_return(pipeline)

        expect(subject.pipeline).to eq(pipeline)
      end
    end

    describe 'when the source project does not exist' do
      it 'returns nil' do
        allow(subject).to receive(:source_project).and_return(nil)

        expect(subject.pipeline).to be_nil
      end
    end
  end

  describe '#all_pipelines' do
    let!(:pipelines) do
      subject.merge_request_diff.commits.map do |commit|
        create(:ci_empty_pipeline, project: subject.source_project, sha: commit.id, ref: subject.source_branch)
      end
    end

    it 'returns a pipelines from source projects with proper ordering' do
      expect(subject.all_pipelines).not_to be_empty
      expect(subject.all_pipelines).to eq(pipelines.reverse)
    end
  end

  describe '#participants' do
    let(:project) { create(:project, :public) }

    let(:mr) do
      create(:merge_request, source_project: project, target_project: project)
    end

    let!(:note1) do
      create(:note_on_merge_request, noteable: mr, project: project, note: 'a')
    end

    let!(:note2) do
      create(:note_on_merge_request, noteable: mr, project: project, note: 'b')
    end

    it 'includes the merge request author' do
      expect(mr.participants).to include(mr.author)
    end

    it 'includes the authors of the notes' do
      expect(mr.participants).to include(note1.author, note2.author)
    end
  end

  describe 'cached counts' do
    it 'updates when assignees change' do
      user1 = create(:user)
      user2 = create(:user)
      mr = create(:merge_request, assignee: user1)

      expect(user1.assigned_open_merge_request_count).to eq(1)
      expect(user2.assigned_open_merge_request_count).to eq(0)

      mr.assignee = user2
      mr.save

      expect(user1.assigned_open_merge_request_count).to eq(0)
      expect(user2.assigned_open_merge_request_count).to eq(1)
    end
  end

  describe '#check_if_can_be_merged' do
    let(:project) { create(:project, only_allow_merge_if_build_succeeds: true) }

    subject { create(:merge_request, source_project: project, merge_status: :unchecked) }

    context 'when it is not broken and has no conflicts' do
      it 'is marked as mergeable' do
        allow(subject).to receive(:broken?) { false }
        allow(project.repository).to receive(:can_be_merged?).and_return(true)

        expect { subject.check_if_can_be_merged }.to change { subject.merge_status }.to('can_be_merged')
      end
    end

    context 'when broken' do
      before { allow(subject).to receive(:broken?) { true } }

      it 'becomes unmergeable' do
        expect { subject.check_if_can_be_merged }.to change { subject.merge_status }.to('cannot_be_merged')
      end
    end

    context 'when it has conflicts' do
      before do
        allow(subject).to receive(:broken?) { false }
        allow(project.repository).to receive(:can_be_merged?).and_return(false)
      end

      it 'becomes unmergeable' do
        expect { subject.check_if_can_be_merged }.to change { subject.merge_status }.to('cannot_be_merged')
      end
    end
  end

  describe '#mergeable?' do
    let(:project) { create(:project) }

    subject { create(:merge_request, source_project: project) }

    it 'returns false if #mergeable_state? is false' do
      expect(subject).to receive(:mergeable_state?) { false }

      expect(subject.mergeable?).to be_falsey
    end

    it 'return true if #mergeable_state? is true and the MR #can_be_merged? is true' do
      allow(subject).to receive(:mergeable_state?) { true }
      expect(subject).to receive(:check_if_can_be_merged)
      expect(subject).to receive(:can_be_merged?) { true }

      expect(subject.mergeable?).to be_truthy
    end
  end

  describe '#mergeable_state?' do
    let(:project) { create(:project) }

    subject { create(:merge_request, source_project: project) }

    it 'checks if merge request can be merged' do
      allow(subject).to receive(:mergeable_ci_state?) { true }
      expect(subject).to receive(:check_if_can_be_merged)

      subject.mergeable?
    end

    context 'when not open' do
      before { subject.close }

      it 'returns false' do
        expect(subject.mergeable_state?).to be_falsey
      end
    end

    context 'when working in progress' do
      before { subject.title = 'WIP MR' }

      it 'returns false' do
        expect(subject.mergeable_state?).to be_falsey
      end
    end

    context 'when broken' do
      before { allow(subject).to receive(:broken?) { true } }

      it 'returns false' do
        expect(subject.mergeable_state?).to be_falsey
      end
    end

    context 'when failed' do
      before { allow(subject).to receive(:broken?) { false } }

      context 'when project settings restrict to merge only if build succeeds and build failed' do
        before do
          project.only_allow_merge_if_build_succeeds = true
          allow(subject).to receive(:mergeable_ci_state?) { false }
        end

        it 'returns false' do
          expect(subject.mergeable_state?).to be_falsey
        end
      end
    end
  end

  describe '#mergeable_ci_state?' do
    let(:project) { create(:empty_project, only_allow_merge_if_build_succeeds: true) }
    let(:pipeline) { create(:ci_empty_pipeline) }

    subject { build(:merge_request, target_project: project) }

    context 'when it is only allowed to merge when build is green' do
      context 'and a failed pipeline is associated' do
        before do
          pipeline.statuses << create(:commit_status, status: 'failed', project: project)
          allow(subject).to receive(:pipeline) { pipeline }
        end

        it { expect(subject.mergeable_ci_state?).to be_falsey }
      end

      context 'when no pipeline is associated' do
        before do
          allow(subject).to receive(:pipeline) { nil }
        end

        it { expect(subject.mergeable_ci_state?).to be_truthy }
      end
    end

    context 'when merges are not restricted to green builds' do
      subject { build(:merge_request, target_project: build(:empty_project, only_allow_merge_if_build_succeeds: false)) }

      context 'and a failed pipeline is associated' do
        before do
          pipeline.statuses << create(:commit_status, status: 'failed', project: project)
          allow(subject).to receive(:pipeline) { pipeline }
        end

        it { expect(subject.mergeable_ci_state?).to be_truthy }
      end

      context 'when no pipeline is associated' do
        before do
          allow(subject).to receive(:pipeline) { nil }
        end

        it { expect(subject.mergeable_ci_state?).to be_truthy }
      end
    end
  end

  describe "#environments" do
    let(:project)       { create(:project) }
    let!(:environment)  { create(:environment, project: project) }
    let!(:environment1) { create(:environment, project: project) }
    let!(:environment2) { create(:environment, project: project) }
    let(:merge_request) { create(:merge_request, source_project: project) }

    it 'selects deployed environments' do
      create(:deployment, environment: environment, sha: project.commit('master').id)
      create(:deployment, environment: environment1, sha: project.commit('feature').id)

      expect(merge_request.environments).to eq [environment]
    end
  end

  describe "#reload_diff" do
    let(:note) { create(:diff_note_on_merge_request, project: subject.project, noteable: subject) }

    let(:commit) { subject.project.commit(sample_commit.id) }

    it "does not change existing merge request diff" do
      expect(subject.merge_request_diff).not_to receive(:save_git_content)
      subject.reload_diff
    end

    it "creates new merge request diff" do
      expect { subject.reload_diff }.to change { subject.merge_request_diffs.count }.by(1)
    end

    it "executs diff cache service" do
      expect_any_instance_of(MergeRequests::MergeRequestDiffCacheService).to receive(:execute).with(subject)

      subject.reload_diff
    end

    it "updates diff note positions" do
      old_diff_refs = subject.diff_refs

      # Update merge_request_diff so that #diff_refs will return commit.diff_refs
      allow(subject).to receive(:create_merge_request_diff) do
        subject.merge_request_diffs.create(
          base_commit_sha: commit.parent_id,
          start_commit_sha: commit.parent_id,
          head_commit_sha: commit.sha
        )

        subject.merge_request_diff(true)
      end

      expect(Notes::DiffPositionUpdateService).to receive(:new).with(
        subject.project,
        nil,
        old_diff_refs: old_diff_refs,
        new_diff_refs: commit.diff_refs,
        paths: note.position.paths
      ).and_call_original

      expect_any_instance_of(Notes::DiffPositionUpdateService).to receive(:execute).with(note)
      expect_any_instance_of(DiffNote).to receive(:save).once

      subject.reload_diff
    end
  end

  describe '#branch_merge_base_commit' do
    context 'source and target branch exist' do
      it { expect(subject.branch_merge_base_commit.sha).to eq('ae73cb07c9eeaf35924a10f713b364d32b2dd34f') }
      it { expect(subject.branch_merge_base_commit).to be_a(Commit) }
    end

    context 'when the target branch does not exist' do
      before do
        subject.project.repository.raw_repository.delete_branch(subject.target_branch)
      end

      it 'returns nil' do
        expect(subject.branch_merge_base_commit).to be_nil
      end
    end
  end

  describe "#diff_sha_refs" do
    context "with diffs" do
      subject { create(:merge_request, :with_diffs) }

      it "does not touch the repository" do
        subject # Instantiate the object

        expect_any_instance_of(Repository).not_to receive(:commit)

        subject.diff_sha_refs
      end

      it "returns expected diff_refs" do
        expected_diff_refs = Gitlab::Diff::DiffRefs.new(
          base_sha:  subject.merge_request_diff.base_commit_sha,
          start_sha: subject.merge_request_diff.start_commit_sha,
          head_sha:  subject.merge_request_diff.head_commit_sha
        )

        expect(subject.diff_sha_refs).to eq(expected_diff_refs)
      end
    end
  end

  context "discussion status" do
    let(:first_discussion) { Discussion.new([create(:diff_note_on_merge_request)]) }
    let(:second_discussion) { Discussion.new([create(:diff_note_on_merge_request)]) }
    let(:third_discussion) { Discussion.new([create(:diff_note_on_merge_request)]) }

    before do
      allow(subject).to receive(:diff_discussions).and_return([first_discussion, second_discussion, third_discussion])
    end

    describe "#discussions_resolvable?" do
      context "when all discussions are unresolvable" do
        before do
          allow(first_discussion).to receive(:resolvable?).and_return(false)
          allow(second_discussion).to receive(:resolvable?).and_return(false)
          allow(third_discussion).to receive(:resolvable?).and_return(false)
        end

        it "returns false" do
          expect(subject.discussions_resolvable?).to be false
        end
      end

      context "when some discussions are unresolvable and some discussions are resolvable" do
        before do
          allow(first_discussion).to receive(:resolvable?).and_return(true)
          allow(second_discussion).to receive(:resolvable?).and_return(false)
          allow(third_discussion).to receive(:resolvable?).and_return(true)
        end

        it "returns true" do
          expect(subject.discussions_resolvable?).to be true
        end
      end

      context "when all discussions are resolvable" do
        before do
          allow(first_discussion).to receive(:resolvable?).and_return(true)
          allow(second_discussion).to receive(:resolvable?).and_return(true)
          allow(third_discussion).to receive(:resolvable?).and_return(true)
        end

        it "returns true" do
          expect(subject.discussions_resolvable?).to be true
        end
      end
    end

    describe "#discussions_resolved?" do
      context "when discussions are not resolvable" do
        before do
          allow(subject).to receive(:discussions_resolvable?).and_return(false)
        end

        it "returns false" do
          expect(subject.discussions_resolved?).to be false
        end
      end

      context "when discussions are resolvable" do
        before do
          allow(subject).to receive(:discussions_resolvable?).and_return(true)

          allow(first_discussion).to receive(:resolvable?).and_return(true)
          allow(second_discussion).to receive(:resolvable?).and_return(false)
          allow(third_discussion).to receive(:resolvable?).and_return(true)
        end

        context "when all resolvable discussions are resolved" do
          before do
            allow(first_discussion).to receive(:resolved?).and_return(true)
            allow(third_discussion).to receive(:resolved?).and_return(true)
          end

          it "returns true" do
            expect(subject.discussions_resolved?).to be true
          end
        end

        context "when some resolvable discussions are not resolved" do
          before do
            allow(first_discussion).to receive(:resolved?).and_return(true)
            allow(third_discussion).to receive(:resolved?).and_return(false)
          end

          it "returns false" do
            expect(subject.discussions_resolved?).to be false
          end
        end
      end
    end
  end

  describe '#conflicts_can_be_resolved_in_ui?' do
    def create_merge_request(source_branch)
      create(:merge_request, source_branch: source_branch, target_branch: 'conflict-start') do |mr|
        mr.mark_as_unmergeable
      end
    end

    it 'returns a falsey value when the MR can be merged without conflicts' do
      merge_request = create_merge_request('master')
      merge_request.mark_as_mergeable

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a falsey value when the MR is marked as having conflicts, but has none' do
      merge_request = create_merge_request('master')

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a falsey value when the MR has a missing ref after a force push' do
      merge_request = create_merge_request('conflict-resolvable')
      allow(merge_request.conflicts).to receive(:merge_index).and_raise(Rugged::OdbError)

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a falsey value when the MR does not support new diff notes' do
      merge_request = create_merge_request('conflict-resolvable')
      merge_request.merge_request_diff.update_attributes(start_commit_sha: nil)

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a falsey value when the conflicts contain a large file' do
      merge_request = create_merge_request('conflict-too-large')

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a falsey value when the conflicts contain a binary file' do
      merge_request = create_merge_request('conflict-binary-file')

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a falsey value when the conflicts contain a file with ambiguous conflict markers' do
      merge_request = create_merge_request('conflict-contains-conflict-markers')

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a falsey value when the conflicts contain a file edited in one branch and deleted in another' do
      merge_request = create_merge_request('conflict-missing-side')

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_falsey
    end

    it 'returns a truthy value when the conflicts are resolvable in the UI' do
      merge_request = create_merge_request('conflict-resolvable')

      expect(merge_request.conflicts_can_be_resolved_in_ui?).to be_truthy
    end
  end
end
