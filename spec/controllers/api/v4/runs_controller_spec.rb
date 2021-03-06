require 'rails_helper'

describe Api::V4::RunsController do
  let(:correct_claim_token) { 'ralph waldo pickle chips!!' }
  let(:incorrect_claim_token) { "i don't know him." }

  describe '#create' do
    let(:run) do
      create(:run)
    end

    context 'when given a cookie' do
      subject(:response) { post :create, params: {file: run.file} }
      let(:u) { build(:user) }
      before { allow(controller).to receive(:current_user) { u } }

      it 'returns a 201' do
        expect(response).to have_http_status 201
      end

      it 'creates a run that belongs to the logged in user' do
        id = JSON.parse(response.body)['id']
        run = Run.find36(id)
        expect(run.user).to eq u
      end
    end

    context 'when given no cookie and no OAuth token' do
      subject(:response) { post :create, params: {file: run.file} }

      it 'returns a 201' do
        expect(response).to have_http_status 201
      end
    end

    context 'when given an invalid OAuth token' do
      subject(:response) { post :create, params: {file: run.file} }

      it 'returns a 401' do
        request.headers['Authorization'] = 'Bearer bad_token'

        expect(response).to have_http_status 401
      end
    end

    context 'when given a valid OAuth token with no scopes' do
      subject(:response) { post :create, params: {file: run.file} }

      it 'returns a 403' do
        authorization = Doorkeeper::AccessToken.create(
          application: Doorkeeper::Application.create(
            name: 'Test Application Please Ignore',
            redirect_uri: 'debug',
            owner: FactoryBot.create(:user)
          ),
          resource_owner_id: FactoryBot.create(:user).id,
        )
        auth_header = "Bearer #{authorization.token}"
        request.headers['Authorization'] = auth_header

        expect(response).to have_http_status 403
      end
    end

    context 'when given a valid OAuth token with an upload_run scope' do
      subject(:response) { post :create, params: {file: run.file} }

      it 'returns a 201' do
        authorization = Doorkeeper::AccessToken.create(
          application: Doorkeeper::Application.create(
            name: 'Test Application Please Ignore',
            redirect_uri: 'debug',
            owner: FactoryBot.create(:user)
          ),
          resource_owner_id: FactoryBot.create(:user).id,
          scopes: 'upload_run'
        )
        request.headers['Authorization'] = "Bearer #{authorization.token}"

        expect(response).to have_http_status 201
      end

      it 'sets the token owner as the run owner' do
        authorization = Doorkeeper::AccessToken.create(
          application: Doorkeeper::Application.create(
            name: 'Test Application Please Ignore',
            redirect_uri: 'debug',
            owner: FactoryBot.create(:user)
          ),
          resource_owner_id: FactoryBot.create(:user).id,
          scopes: 'upload_run'
        )
        request.headers['Authorization'] = "Bearer #{authorization.token}"

        expect(Run.find36(JSON.parse(response.body)['id']).user).to eq(User.find(authorization.resource_owner_id))
      end
    end
  end

  describe '#show' do
    context 'for a nonexistent run' do
      subject { get :show, params: {run: '0'} }

      it 'returns a 404' do
        expect(subject).to have_http_status 404
      end
    end

    context 'for a bogus ID' do
      subject { get :show, params: {run: '/@??$@;[1;?'} }

      it 'returns a 404' do
        expect(subject).to have_http_status 404
      end
    end

    context 'for an existing run' do
      let(:run) { create(:run, :owned, :parsed) }
      subject { get :show, params: {run: run.id36} }
      let(:body) { JSON.parse(subject.body)['run'] }

      it 'returns a 200' do
        expect(subject).to have_http_status 200
      end

      it 'renders a run schema' do
        expect(subject.body).to match_json_schema(:run)
      end

      it 'has no history present' do
        expect(body['histories']).to be_nil
      end

      it 'has no segment histories present' do
        body['segments'].each do |segment|
          expect(segment['histories']).to be_nil
        end
      end
    end

    context 'for an existing run with historic=1' do
      let(:run) { create(:run, :owned, :parsed) }
      subject { get :show, params: {run: run.id36, historic: '1'} }
      let(:body) { JSON.parse(subject.body)['run'] }

      it 'returns a 200' do
        expect(subject).to have_http_status 200
      end

      it 'renders a run schema' do
        expect(subject.body).to match_json_schema(:run)
      end

      it 'has a history present' do
        expect(body['histories']).not_to be_nil
      end

      it 'has segment histories present' do
        body['segments'].each do |segment|
          expect(segment['histories']).not_to be_nil
        end
      end
    end

    context 'for an existing run with a valid accept header' do
      let(:run) { create(:run, :owned, :parsed) }
      subject(:response) { get :show, params: {run: run.id36} }

      it 'returns a 200' do
        request.headers['Accept'] = 'application/wsplit'

        expect(subject).to have_http_status 200
      end

      it 'returns the correct content-type header' do
        request.headers['Accept'] = 'application/wsplit'

        expect(response.media_type).to eq('application/wsplit')
      end
    end

    context 'for an existing run with a bogus accept header' do
      let(:run) { create(:run, :owned, :parsed) }
      subject(:response) { get :show, params: {run: run.id36} }

      it 'returns a 406' do
        request.headers['Accept'] = 'application/liversplit'

        expect(subject).to have_http_status 406
      end

      it 'returns the correct content-type header' do
        request.headers['Accept'] = 'application/liversplit'

        expect(response.media_type).to eq('application/json')
      end
    end

    context 'for an existing run with a valid original timer accept header' do
      let(:run) { create(:run, :owned, :parsed) }
      subject(:response) { get :show, params: {run: run.id36} }

      it 'returns a 200' do
        request.headers['Accept'] = 'application/original-timer'

        expect(subject).to have_http_status 200
      end

      it 'returns the correct content-type header' do
        request.headers['Accept'] = 'application/original-timer'

        expect(response.media_type).to eq('application/livesplit')
      end
    end
  end

  describe '#update' do
    let(:old_srdc_id) { 'throw a blanket over it!' }
    let(:new_srdc_id) { 'put a little fence around it!' }

    context 'with no claim token' do
      subject { put :update, params: {run: run.id36, srdc_id: new_srdc_id} }

      context 'when the run has a null claim token' do
        let(:run) { create(:run, claim_token: nil) }

        it 'returns a 401' do
          expect(subject).to have_http_status 401
        end
      end

      context 'when the run has a claim token' do
        let(:run) { create(:run, claim_token: correct_claim_token) }

        it 'returns a 401' do
          expect(subject).to have_http_status 401
        end
      end
    end

    context 'with a non-matching claim token' do
      let(:run) { create(:run, claim_token: correct_claim_token, srdc_id: old_srdc_id) }
      subject { put :update, params: {run: run.id36, srdc_id: old_srdc_id, claim_token: incorrect_claim_token} }

      it 'returns a 403' do
        expect(subject).to have_http_status 403
      end
    end

    context 'with a matching claim token' do
      let(:run) { create(:run, claim_token: correct_claim_token, srdc_id: old_srdc_id) }
      subject { put :update, params: {run: run.id36, srdc_id: new_srdc_id, claim_token: correct_claim_token} }

      it 'returns a 204' do
        expect(subject).to have_http_status 204
      end
    end
  end

  describe '#destroy' do
    context 'when given an invalid OAuth token' do
      context 'on an existing run' do
        let(:run) { create(:run) }
        subject { delete :destroy, params: {run: run.id36} }

        it 'returns a 401' do
          request.headers['Authorization'] = 'Bearer bad_token'

          expect(subject).to have_http_status 401
        end
      end

      context 'on a nonexisting run' do
        subject { delete :destroy, params: {run: '0'} }

        it 'returns a 404' do
          expect(subject).to have_http_status 404
        end
      end
    end

    context 'when given a valid OAuth token with no scopes for the right user' do
      let(:run) { FactoryBot.create(:run, :owned) }
      subject { delete :destroy, params: {run: run.id36} }
      let(:authorization) do
        Doorkeeper::AccessToken.create(
          application: Doorkeeper::Application.create(
            name: 'Test Application Please Ignore',
            redirect_uri: 'debug',
            owner: FactoryBot.create(:user)
          ),
          resource_owner_id: run.user.id
        )
      end

      it 'returns a 403' do
        request.headers['Authorization'] = "Bearer #{authorization.token}"

        expect(subject).to have_http_status :forbidden
      end
    end

    context 'when given a valid OAuth token with a delete_run scope for the right user' do
      let(:run) { FactoryBot.create(:run, :owned) }
      subject { delete :destroy, params: {run: run.id36} }
      let(:authorization) do
        Doorkeeper::AccessToken.create(
          application: Doorkeeper::Application.create(
            name: 'Test Application Please Ignore',
            redirect_uri: 'debug',
            owner: FactoryBot.create(:user)
          ),
          resource_owner_id: run.user.id,
          scopes: 'delete_run'
        )
      end


      it 'returns a 205' do
        request.headers['Authorization'] = "Bearer #{authorization.token}"

        expect(subject).to have_http_status 205
      end
    end
    context 'when given a valid OAuth token with a delete_run scope for the wrong user' do
      let(:run) { FactoryBot.create(:run, :owned) }
      subject { delete :destroy, params: {run: run.id36} }
      let(:authorization) do
        Doorkeeper::AccessToken.create(
          application: Doorkeeper::Application.create(
            name: 'Test Application Please Ignore',
            redirect_uri: 'debug',
            owner: FactoryBot.create(:user)
          ),
          resource_owner_id: FactoryBot.create(:user).id,
          scopes: 'delete_run'
        )
      end


      it 'returns a 401' do
        request.headers['Authorization'] = "Bearer #{authorization.token}"

        expect(subject).to have_http_status :unauthorized
      end
    end
  end
end
