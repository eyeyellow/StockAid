module UsersHelper
  def additional_organizations_json(user, organizations)
    organizations.drop(1).map do |organization|
      {
        name: organization.name,
        role: user.role_at(organization),
        href: edit_organization_path(organization, redirect_to: "users")
      }
    end.to_json
  end
end
