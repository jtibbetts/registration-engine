class ToolProfilesController < ApplicationController

  def get_first
    tool = Lti2Tp::Tool.first
    render json: JSON.pretty_generate(tool.get_tool_profile)
  end
end
