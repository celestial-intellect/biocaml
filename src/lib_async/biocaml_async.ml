module Lines = struct
  include Biocaml_lines
  include MakeIO(Future_async)
end

module Fastq = struct
  include Biocaml_fastq
  include MakeIO(Future_async)
end