/// The Shadow version shared by the CLI (`shadow --version`), JSON reports and
/// the app when it runs outside a bundle. scripts/bump-version.sh rewrites it
/// and scripts/check-versions.sh keeps it equal to VERSION and Info.plist.
public enum ShadowVersion {
    public static let current = "1.0.0"
}
