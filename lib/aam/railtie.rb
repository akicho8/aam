module Aam
  class Railtie < Rails::Railtie
    rake_tasks do
      load "aam/tasks/aam.rake"
    end
  end
end
