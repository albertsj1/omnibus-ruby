require 'spec_helper'

module Omnibus
  describe S3Cache do
    let(:ruby_19) { double(name: 'ruby', version: '1.9.3', checksum: 'abcd1234') }
    let(:python_27) { double(name: 'python', version: '2.7', checksum: 'defg5678') }

    describe '.list' do
      let(:keys) { %w(ruby-1.9.3-abcd1234 python-2.7.defg5678) }
      let(:softwares) { [ruby_19, python_27] }

      before do
        allow(S3Cache).to receive(:keys).and_return(keys)
        allow(S3Cache).to receive(:softwares).and_return(softwares)
      end

      it 'lists the software that is cached on S3' do
        expect(S3Cache.list).to include(ruby_19)
        expect(S3Cache.list).to_not include(python_27)
      end
    end

    describe '.keys' do
      let(:bucket) { double(:bucket, objects: []) }

      before { S3Cache.stub(:bucket).and_return(bucket) }

      it 'lists the keys on the S3 bucket' do
        expect(bucket).to receive(:objects).with('/').once
        S3Cache.keys
      end
    end

    describe '.missing' do
      let(:keys) { %w(ruby-1.9.3-abcd1234 python-2.7.defg5678) }
      let(:softwares) { [ruby_19, python_27] }

      before do
        allow(S3Cache).to receive(:keys).and_return(keys)
        allow(S3Cache).to receive(:softwares).and_return(softwares)
      end

      it 'lists the software that is cached on S3' do
        expect(S3Cache.missing).to_not include(ruby_19)
        expect(S3Cache.missing).to include(python_27)
      end
    end

    describe '.populate' do
      it 'pending a good samaritan to come along and write tests...'
    end

    describe '.fetch_missing' do
      let(:softwares) { [ruby_19, python_27] }

      before { S3Cache.stub(:missing).and_return(softwares) }

      it 'fetches the missing software' do
        expect(S3Cache).to receive(:fetch).with(ruby_19)
        expect(S3Cache).to receive(:fetch).with(python_27)

        S3Cache.fetch_missing
      end
    end

    describe '.key_for' do
      context 'when the package does not have a name' do
        it 'raises an exception' do
          expect { S3Cache.key_for(double(name: nil)) }
            .to raise_error(InsufficientSpecification)
        end
      end

      context 'when the package does not have a version' do
        it 'raises an exception' do
          expect { S3Cache.key_for(double(name: 'ruby', version: nil)) }
            .to raise_error(InsufficientSpecification)
        end
      end

      context 'when the package does not have a checksum' do
        it 'raises an exception' do
          expect { S3Cache.key_for(double(name: 'ruby', version: '1.9.3', checksum: nil)) }
            .to raise_error(InsufficientSpecification)
        end
      end

      it 'returns the correct string' do
        expect(S3Cache.key_for(ruby_19)).to eq('ruby-1.9.3-abcd1234')
      end
    end
  end
end
